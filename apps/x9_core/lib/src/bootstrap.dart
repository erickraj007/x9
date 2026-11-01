import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'api.dart';
import 'server_settings.dart';
import 'startup_log.dart';
import 'ui/error_panel.dart';
import 'ui/dialogs.dart';
import 'ui/txn_otp_dialog.dart';

/// Holds what [runX9App] needs to start the app again ("Retry" on the error screen).
class X9Bootstrap {
  X9Bootstrap._();

  /// The app's root navigator key (given to [runX9App]); lets the error panel open Server settings even when
  /// it is drawn outside a Navigator.
  static GlobalKey<NavigatorState>? navigatorKey;

  static Widget Function()? _app;
  static List<Future<void> Function()> _steps = const [];
  static List<String> _names = const [];
  static Duration _stepTimeout = const Duration(seconds: 5);
  static Duration _budget = const Duration(seconds: 12);
  static bool _restarting = false;

  /// Runs the init steps again and rebuilds the whole app from scratch. Used by the error panel's Retry.
  static Future<void> restart() async {
    if (_restarting || _app == null) return;
    _restarting = true;
    try {
      StartupLog.add('Restart requested');
      _safeRunApp(const _BootSplash());
      await _runAll();
      _launch();
    } catch (e, st) {
      StartupLog.error('restart', e, st);
    } finally {
      _restarting = false;
    }
  }

  static Future<void> _runAll() async {
    try {
      await StartupLog.loadPrevious();
    } catch (_) {}
    await _runStep('server address', ServerSettings.load);
    final clock = Stopwatch()..start();
    for (var i = 0; i < _steps.length; i++) {
      if (clock.elapsed > _budget) {
        // Startup is taking too long overall: show the app now and let the remaining steps finish behind it.
        StartupLog.add('Startup budget of ${_budget.inSeconds}s used up - ${_steps.length - i} step(s) continue in the background');
        final from = i;
        unawaited(() async {
          for (var j = from; j < _steps.length; j++) {
            await _runStep(_nameOf(j), _steps[j]);
          }
        }());
        return;
      }
      await _runStep(_nameOf(i), _steps[i]);
    }
  }

  static String _nameOf(int i) => i < _names.length ? _names[i] : 'step ${i + 1}';

  static Future<void> _runStep(String name, Future<void> Function() step) async {
    try {
      await step().timeout(_stepTimeout);
    } on TimeoutException {
      StartupLog.add('Init "$name" did not finish within ${_stepTimeout.inSeconds}s - continuing without it');
    } catch (e, st) {
      StartupLog.error('Init "$name" failed', e, st);
    }
  }

  static void _launch() {
    try {
      final build = _app!;
      runApp(KeyedSubtree(key: UniqueKey(), child: build()));
    } catch (e, st) {
      StartupLog.error('building the app', e, st);
      _safeRunApp(_FatalApp(error: '$e'));
    }
  }

  static void _safeRunApp(Widget w) {
    try {
      runApp(w);
    } catch (e, st) {
      StartupLog.error('runApp', e, st);
    }
  }

  static void _installErrorHandlers() {
    FlutterError.onError = (FlutterErrorDetails d) {
      StartupLog.error('Flutter error', d.exception, d.stack);
      try {
        FlutterError.presentError(d);
      } catch (_) {}
    };
    PlatformDispatcher.instance.onError = (Object e, StackTrace st) {
      StartupLog.error('Platform error', e, st);
      return true; // handled: do not crash the app
    };
    ErrorWidget.builder = (FlutterErrorDetails d) {
      StartupLog.error('Build error', d.exception, d.stack);
      try {
        return X9ErrorPanel.fromFlutterError(d);
      } catch (_) {
        return const SizedBox.shrink();
      }
    };
  }
}

/// Starts an X9 app so that it can never end on a blank screen.
///
/// * everything runs inside `runZonedGuarded`; Flutter / platform / zone errors go to the [StartupLog]
/// * a widget that throws while building is replaced by a readable error panel (message, Retry, Server settings)
/// * a plain "Starting..." screen is shown at once, then every [initSteps] entry runs in order, each in its own
///   try/catch with [stepTimeout] (default 5 s; on timeout startup continues without waiting for it)
/// * `runApp(app())` is ALWAYS called, even when steps failed or [app] itself threw
///
/// The compiled-in server address and the saved Server-settings override are loaded first.
Future<void> runX9App({
  required Widget Function() app,
  required List<Future<void> Function()> initSteps,
  List<String> stepNames = const <String>[],
  Duration stepTimeout = const Duration(seconds: 5),
  Duration totalBudget = const Duration(seconds: 12),
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final done = Completer<void>();
  runZonedGuarded<void>(() {
    () async {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        X9Bootstrap._app = app;
        X9Bootstrap._steps = initSteps;
        X9Bootstrap._names = stepNames;
        X9Bootstrap._stepTimeout = stepTimeout;
        X9Bootstrap._budget = totalBudget;
        X9Bootstrap.navigatorKey = navigatorKey;
        Api.instance.txnOtpPrompt = showTxnOtpDialog;
        Api.instance.mpinPrompt = showMpinSheet;
        Api.instance.confirmPrompt = showConfirmForRequest;
        X9Bootstrap._installErrorHandlers();
        X9Bootstrap._safeRunApp(const _BootSplash());
        try {
          await X9Bootstrap._runAll();
        } catch (e, st) {
          StartupLog.error('startup', e, st);
        }
        X9Bootstrap._launch();
      } catch (e, st) {
        StartupLog.error('runX9App', e, st);
        X9Bootstrap._safeRunApp(_FatalApp(error: '$e'));
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }();
  }, (Object e, StackTrace st) {
    StartupLog.error('Uncaught', e, st);
  });
  return done.future;
}

/// Shown while the init steps run (plain colours, no assets).
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFFFFFFFF),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('X9', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: Color(0xFFE61C24), decoration: TextDecoration.none)),
              SizedBox(height: 20),
              SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFE61C24))),
            ]),
          ),
        ),
      );
}

/// Last resort when the app widget itself could not be created.
class _FatalApp extends StatelessWidget {
  const _FatalApp({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: X9Bootstrap.navigatorKey,
        home: Scaffold(
          body: X9ErrorPanel(
            title: 'X9 could not start',
            message: 'The app could not start. Please try again.',
            detail: error,
            onRetry: X9Bootstrap.restart,
            forceFull: true,
          ),
        ),
      );
}
