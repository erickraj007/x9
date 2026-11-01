import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import 'screens/appointments/appointments_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/offers/offer_detail_screen.dart';
import 'screens/payment_links/payment_links_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/setup/device_setup_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'services/deep_link.dart';
import 'services/location.dart';
import 'services/push.dart';
import 'state/app_state.dart';
import 'util/helpers.dart';

class X9UserApp extends StatelessWidget {
  const X9UserApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the person picks Light / Dark / System in Profile (default: Light).
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'X9',
        debugShowCheckedModeBanner: false,
        theme: x9LightTheme(),
        darkTheme: x9DarkTheme(),
        themeMode: ThemeController.instance.mode,
        navigatorKey: rootNavKey,
        home: const RootGate(),
      ),
    );
  }
}

enum _Stage { loading, login, lockSetup, locked, device, home, error }

/// Decides what the person sees: sign-in → app lock setup → unlock → phone approval (MPIN + device key) → home.
/// Also re-locks the app after it was in the background longer than X9Config.relockAfter.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  _Stage _stage = _Stage.loading;
  bool _unlockedThisRun = false;
  bool _hasMpin = true;
  Object? _error;
  bool _lockShown = false;
  int _gen = 0;

  Timer? _watchdog;

  /// The loading stage may never last longer than this: after it the error stage (real error text, Retry,
  /// Server settings) is shown instead of an endless spinner.
  static const Duration _loadingLimit = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    try {
      WidgetsBinding.instance.addObserver(this);
      AppState.instance.onSessionChanged = _route;
      Api.instance.onUnauthorized = () => AppState.instance.signOut(server: false);
      PushService.instance.onOpen = _openPush;
    } catch (e, st) {
      StartupLog.error('RootGate init', e, st);
    }
    try {
      DeepLinkService.instance.onOffer = _openOffer;
      DeepLinkService.instance.start().catchError((Object e, StackTrace st) => StartupLog.error('deep links', e, st));
    } catch (e, st) {
      StartupLog.error('deep links', e, st);
    }
    _route();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    try {
      DeepLinkService.instance.onOffer = null;
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _set(_Stage s) {
    _watchdog?.cancel();
    _watchdog = null;
    if (!mounted) return;
    setState(() => _stage = s);
    if (s == _Stage.loading) {
      final gen = _gen;
      _watchdog = Timer(_loadingLimit, () {
        if (!mounted || gen != _gen || _stage != _Stage.loading) return;
        _gen++; // whatever the stuck request returns later is ignored
        _error = TimeoutException('Still waiting after ${_loadingLimit.inSeconds} seconds');
        StartupLog.add('Startup watchdog: $_error');
        _set(_Stage.error);
      });
    }
  }

  Future<void> _route() async {
    final gen = ++_gen;
    try {
      await _routeImpl(gen);
    } catch (e, st) {
      StartupLog.error('startup route', e, st);
      if (gen != _gen) return;
      _error = e;
      _set(_Stage.error);
    }
  }

  Future<void> _routeImpl(int gen) async {
    final s = SessionStore.instance;
    if (!s.signedIn) {
      _unlockedThisRun = true; // a fresh sign-in proves it is the owner
      _set(_Stage.login);
      return;
    }
    if (!AppLock.instance.isSetUp) {
      _set(_Stage.lockSetup);
      return;
    }
    if (!_unlockedThisRun) {
      _set(_Stage.locked);
      return;
    }
    if (_stage != _Stage.home) _set(_Stage.loading);
    final key = await s.deviceKey().timeout(const Duration(seconds: 3), onTimeout: () => null);
    try {
      final p = asMap(await Api.instance.get('/app/profile').timeout(const Duration(seconds: 8)));
      if (gen != _gen) return;
      await saveProfileUser(p);
      _hasMpin = p['has_mpin'] == null ? true : asBool(p['has_mpin']);
      final registered = asBool(p['device_registered']) && key != null;
      if (!registered) {
        if (gen == _gen) _set(_Stage.device);
        return;
      }
    } catch (e) {
      if (gen != _gen || !SessionStore.instance.signedIn) return;
      if (key == null || (e is ApiException && (e.code == 'BAD_RESPONSE' || e.code == 'TLS'))) {
        _error = e;
        _set(_Stage.error);
        return;
      }
      // Offline with an approved key: continue; screens show their own errors.
    }
    if (gen != _gen) return;
    _set(_Stage.home);
    _safely('push registration', () => PushService.instance.registerToken());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        PushService.instance.flushPending();
        DeepLinkService.instance.flushPending();
      } catch (e, st) {
        StartupLog.error('pending push / link', e, st);
      }
    });
  }

  /// Runs [job] without letting an exception escape (fire-and-forget start-up work).
  void _safely(String what, FutureOr<void> Function() job) {
    try {
      final r = job();
      if (r is Future<void>) r.catchError((Object e, StackTrace st) => StartupLog.error(what, e, st));
    } catch (e, st) {
      StartupLog.error(what, e, st);
    }
  }

  /// x9://offer/CODE or https://HOST/o/CODE: opens the offer once the person is signed in and unlocked.
  void _openOffer(String ref) {
    if (_stage != _Stage.home || _lockShown) {
      DeepLinkService.instance.pendingRef = ref;
      return;
    }
    rootNavKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => OfferDetailScreen(refId: ref)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      if (state == AppLifecycleState.paused) {
        AppLock.instance.markBackground();
        LocationService.instance.stopHeartbeat();
      } else if (state == AppLifecycleState.resumed) {
        final relock = AppLock.instance.shouldRelock();
        if (_stage == _Stage.home && SessionStore.instance.signedIn) {
          if (relock) _showLockRoute();
          LocationService.instance.startHeartbeat();
          _safely('location heartbeat', () => LocationService.instance.send());
        }
      }
    } catch (e, st) {
      StartupLog.error('lifecycle', e, st);
    }
  }

  void _showLockRoute() {
    final nav = rootNavKey.currentState;
    if (_lockShown || nav == null) return;
    _lockShown = true;
    var done = false;
    nav.push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, a1, a2) => PopScope(
        canPop: false,
        child: LockScreen(
          onUnlocked: () {
            if (done) return;
            done = true;
            _lockShown = false;
            nav.pop();
          },
          onForgot: () {
            done = true;
            _lockShown = false;
            AppState.instance.signOut();
          },
        ),
      ),
    ));
  }

  void _openPush(Map<String, dynamic> data) {
    if (_stage != _Stage.home || _lockShown) {
      PushService.instance.pendingOpen = data;
      return;
    }
    final nav = rootNavKey.currentState;
    if (nav == null) return;
    final kind = '${data['type'] ?? ''} ${data['screen'] ?? ''} ${data['event'] ?? ''}'.toUpperCase();
    if (kind.contains('CASHBACK')) {
      AppState.instance.refreshBalances();
      nav.push(MaterialPageRoute<void>(builder: (_) => const WalletScreen()));
    } else if (kind.contains('ORDER_UPDATE')) {
      nav.push(MaterialPageRoute<void>(builder: (_) => const OrdersScreen())); // v6.17 order tracking
    } else if (kind.contains('APPOINTMENT_UPDATE')) {
      nav.push(MaterialPageRoute<void>(builder: (_) => const AppointmentsScreen()));
    } else if (kind.contains('PAYMENT_LINK') || kind.contains('PAYMENT_REQUEST')) {
      AppState.instance.refreshFeed();
      nav.push(MaterialPageRoute<void>(builder: (_) => const PaymentLinksScreen()));
    } else {
      nav.push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));
    }
  }

  /// Technical text for the error stage: the real exception (and the network cause for API errors).
  String _errorDetail(Object? e) {
    if (e == null) return '';
    final b = StringBuffer(e.runtimeType.toString());
    if (e is ApiException) {
      b.write(' (HTTP ${e.status}${e.code == null ? '' : ', ${e.code}'}): ${e.full}');
    } else {
      b.write(': $e');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (_stage) {
      case _Stage.loading:
        child = const _Splash();
        break;
      case _Stage.login:
        child = const WelcomeScreen();
        break;
      case _Stage.lockSetup:
        child = LockSetupPage(onDone: () {
          _unlockedThisRun = true;
          _route();
        });
        break;
      case _Stage.locked:
        child = LockScreen(
          onUnlocked: () {
            if (_unlockedThisRun) return;
            _unlockedThisRun = true;
            _route();
          },
          onForgot: () => AppState.instance.signOut(),
        );
        break;
      case _Stage.device:
        child = DeviceSetupScreen(hasMpin: _hasMpin, onDone: _route);
        break;
      case _Stage.error:
        child = Scaffold(
          body: X9ErrorPanel(
            title: 'Could not start X9',
            message: friendlyError(_error ?? 'Something went wrong'),
            detail: _errorDetail(_error),
            onRetry: _route,
            forceFull: true,
            extraActions: [
              X9ErrorPanel.plainButton('Sign out', () => AppState.instance.signOut()),
            ],
          ),
        );
        break;
      case _Stage.home:
        child = const HomeScreen();
        break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(key: ValueKey(_stage), child: child),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            X9Logo(height: 150),
            SizedBox(height: 28),
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
          ]),
        ),
      );
}
