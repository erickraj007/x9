import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../bootstrap.dart';
import '../config.dart';
import '../connection_test.dart';
import '../server_settings.dart';
import '../startup_log.dart';

/// Opens [ServerSettingsScreen] on the root navigator (falls back to the navigator key given to [runX9App]).
/// Completes with true when the address was changed. Never throws.
Future<bool?> openServerSettings(BuildContext context) async {
  if (!ServerSettingsAccess.enabled) return null;
  try {
    final nav = Navigator.maybeOf(context, rootNavigator: true) ?? X9Bootstrap.navigatorKey?.currentState;
    if (nav == null) return null;
    return await nav.push<bool>(MaterialPageRoute<bool>(builder: (_) => const ServerSettingsScreen()));
  } catch (e, st) {
    StartupLog.error('open server settings', e, st);
    return null;
  }
}

/// Apps that ship to shops switch the Server settings entry points off (merchant app); the address is compiled in.
class ServerSettingsAccess {
  /// Off everywhere unless a private test build passes `--dart-define=X9_SHOW_TECH=true`.
  static bool enabled = const bool.fromEnvironment('X9_SHOW_TECH', defaultValue: false);
}

/// Small "Server settings" text link for the bottom of welcome / login screens.
class ServerSettingsLink extends StatelessWidget {
  const ServerSettingsLink({super.key, this.onChanged});

  /// Called after the screen closes with a changed address.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final changed = await openServerSettings(context);
          if (changed == true) onChanged?.call();
        },
        icon: const Icon(Icons.dns_outlined, size: 16),
        label: const Text('Server settings'),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12.5)),
      ),
    );
  }
}

/// Wrap the logo: a long press opens the Server settings screen.
class ServerSettingsLongPress extends StatelessWidget {
  const ServerSettingsLongPress({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => openServerSettings(context),
        child: child,
      );
}

/// Change the server address on the phone, test it and copy diagnostics for support.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final TextEditingController _c = TextEditingController(text: ServerSettings.override ?? '');
  bool _changed = false;
  bool _testing = false;
  List<ProbeResult>? _results;
  String? _verdict;
  String? _testedBase;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  ({String? value, String? error}) get _parsed => ServerSettings.normalize(_c.text);

  /// The address to test: what is typed when valid, else the one in use.
  String get _target => _c.text.trim().isEmpty ? ServerSettings.effectiveApiBase : (_parsed.value ?? ServerSettings.effectiveApiBase);

  Future<void> _test() async {
    if (_c.text.trim().isNotEmpty && _parsed.value == null) {
      setState(() => _verdict = _parsed.error);
      return;
    }
    final base = _target;
    setState(() {
      _testing = true;
      _results = null;
      _verdict = null;
      _testedBase = base;
    });
    List<ProbeResult> r;
    try {
      r = await ServerConnectionTest.run(base);
    } catch (e) {
      r = [ProbeResult('test', base)..error = '$e'];
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _results = r;
      _verdict = ServerConnectionTest.verdict(r);
    });
  }

  Future<void> _save() async {
    final p = _parsed;
    if (p.value == null) {
      setState(() {});
      return;
    }
    try {
      final v = await ServerSettings.save(_c.text);
      _changed = true;
      if (!mounted) return;
      _c.text = v;
      setState(() {});
      _snack('Saved. The app now uses $v');
    } catch (e) {
      if (mounted) _snack('Could not save: $e');
    }
  }

  Future<void> _reset() async {
    await ServerSettings.reset();
    _changed = true;
    if (!mounted) return;
    _c.text = '';
    setState(() {
      _results = null;
      _verdict = null;
    });
    _snack('Back to the built-in address: ${X9Config.defaultApiBase}');
  }

  String _diagnostics() {
    final b = StringBuffer()
      ..writeln('X9 diagnostics')
      ..writeln('App: ${Api.instance.appName} ${Api.instance.appVersion}')
      ..writeln('Time: ${DateTime.now().toIso8601String()}')
      ..writeln('Built-in address: ${X9Config.defaultApiBase}  (API_BASE define: "${X9Config.apiBase}")')
      ..writeln('Saved override: ${ServerSettings.override ?? '(none)'}')
      ..writeln('In use: ${ServerSettings.effectiveApiBase}')
      ..writeln('ALLOW_SELF_SIGNED: ${X9Config.allowSelfSigned}; self-signed trusted for host: ${ServerSettings.trustsCertificate(ServerSettings.effectiveHost)}');
    final r = _results;
    if (r != null) {
      b.writeln('\nConnection test of $_testedBase:');
      for (final p in r) {
        b.writeln('${p.url}\n  ${p.summary.replaceAll('\n', '\n  ')}');
      }
      if (_verdict != null) b.writeln('Verdict: $_verdict');
    }
    b
      ..writeln('\nStartup log:')
      ..writeln(StartupLog.dump());
    return b.toString();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _diagnostics()));
    if (mounted) _snack('Diagnostics copied. Paste them to X9 support.');
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4);
    final typed = _c.text.trim().isNotEmpty;
    final p = _parsed;
    final logLines = StartupLog.lines;
    final shown = logLines.length > 12 ? logLines.sublist(logLines.length - 12) : logLines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server settings'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop(_changed)),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Address of the X9 server this app talks to. Change it only if X9 support tells you to, or if the app cannot connect.', style: muted),
        const SizedBox(height: 14),
        Text('In use now', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        SelectableText(ServerSettings.effectiveApiBase),
        Text(ServerSettings.hasOverride ? 'Set on this phone' : 'Built-in address', style: muted),
        const SizedBox(height: 18),
        TextField(
          controller: _c,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Server address',
            hintText: 'https://api.example.com/api/v1',
            errorText: typed ? p.error : null,
            helperText: typed && p.value != null ? 'Will use: ${p.value}' : 'Only the host is enough, /api/v1 is added.',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton(onPressed: typed && p.value != null ? _save : null, child: const Text('Save')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: const Text('Test connection'),
          ),
          const SizedBox(height: 6),
          TextButton(onPressed: ServerSettings.hasOverride || typed ? _reset : null, child: const Text('Reset to default')),
        ]),
        if (_verdict != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_verdict!, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_results != null) ...[
                const SizedBox(height: 8),
                for (final r in _results!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText(r.summary, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35)),
                  ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 22),
        Text('Startup log', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: SelectableText(
            shown.isEmpty ? 'No startup problems recorded.' : shown.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _copy, icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Copy diagnostics')),
        const SizedBox(height: 8),
        Text('${Api.instance.appName} ${Api.instance.appVersion}', style: muted),
      ]),
    );
  }
}
