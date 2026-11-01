import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'config.dart';
import 'session.dart';
import 'ui/logo.dart';
import 'ui/pin_pattern.dart';
import 'ui/theme.dart';

enum LockMethod { pin, pattern }

/// Device access: the app opens only after PIN / pattern / fingerprint / face, and every
/// money movement asks again (AppLock.confirm) before the request is signed with the device key.
class AppLock {
  AppLock._();
  static final AppLock instance = AppLock._();

  final LocalAuthentication _auth = LocalAuthentication();

  LockMethod? method;
  bool biometric = false;
  String? _secretHash;
  String? _salt;
  int _failed = 0;
  DateTime? _backgroundAt;

  bool get isSetUp => method != null && _secretHash != null;

  Future<void> load() async {
    final s = SessionStore.instance;
    final m = await s.read('lock_method');
    method = m == 'pattern' ? LockMethod.pattern : m == 'pin' ? LockMethod.pin : null;
    biometric = (await s.read('lock_biometric')) == '1';
    _secretHash = await s.read('lock_hash');
    _salt = await s.read('lock_salt');
  }

  Future<bool> biometricAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setUp(LockMethod m, String secret, {required bool useBiometric}) async {
    final s = SessionStore.instance;
    _salt = SessionStore.newIdempotencyKey();
    method = m;
    biometric = useBiometric;
    _secretHash = _hash(secret);
    await s.write('lock_method', m == LockMethod.pin ? 'pin' : 'pattern');
    await s.write('lock_biometric', useBiometric ? '1' : '0');
    await s.write('lock_salt', _salt);
    await s.write('lock_hash', _secretHash);
  }

  Future<void> reset() async {
    final s = SessionStore.instance;
    method = null;
    biometric = false;
    _secretHash = null;
    for (final k in ['lock_method', 'lock_biometric', 'lock_salt', 'lock_hash']) {
      await s.write(k, null);
    }
  }

  String _hash(String secret) => sha256.convert(utf8.encode('${_salt ?? ''}:$secret')).toString();

  bool check(String secret) {
    final ok = _secretHash != null && _hash(secret) == _secretHash;
    _failed = ok ? 0 : _failed + 1;
    return ok;
  }

  int get failedAttempts => _failed;

  Future<bool> tryBiometric(String reason) async {
    if (!biometric) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    }
  }

  void markBackground() => _backgroundAt = DateTime.now();

  bool shouldRelock() {
    final at = _backgroundAt;
    _backgroundAt = null;
    return isSetUp && at != null && DateTime.now().difference(at) > X9Config.relockAfter;
  }

  /// Ask the person to prove it is them before a transaction / card details.
  /// Returns true when unlocked by fingerprint/face, PIN or pattern.
  Future<bool> confirm(BuildContext context, {String reason = 'Confirm to continue'}) async {
    if (!isSetUp) return true; // the app forces lock setup at sign-in; this is a safety net
    if (biometric && await tryBiometric(reason)) return true;
    if (!context.mounted) return false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        child: UnlockPanel(title: reason, onUnlocked: () => Navigator.of(context).pop(true)),
      ),
    );
    return ok == true;
  }
}

/// PIN pad or pattern, whichever the person chose; offers fingerprint/face when enabled.
class UnlockPanel extends StatefulWidget {
  const UnlockPanel({super.key, required this.title, required this.onUnlocked, this.subtitle});
  final String title;
  final String? subtitle;
  final VoidCallback onUnlocked;

  @override
  State<UnlockPanel> createState() => _UnlockPanelState();
}

class _UnlockPanelState extends State<UnlockPanel> {
  String? _error;

  void _submit(String secret) {
    final lock = AppLock.instance;
    if (lock.check(secret)) {
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _error = lock.failedAttempts >= 5 ? 'Too many tries. Sign in again to reset.' : 'Wrong ${lock.method == LockMethod.pin ? 'PIN' : 'pattern'}. Try again.');
    }
  }

  Future<void> _bio() async {
    if (await AppLock.instance.tryBiometric(widget.title)) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_rounded, color: X9Colors.primary, size: 30),
      const SizedBox(height: 8),
      Text(widget.title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      if (widget.subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.subtitle!, style: TextStyle(color: context.x9.textSecondary))),
      const SizedBox(height: 18),
      if (lock.method == LockMethod.pattern) ...[
        PatternLock(onCompleted: _submit, error: _error != null, size: 260),
        const SizedBox(height: 8),
        Text(_error ?? 'Draw your pattern', style: TextStyle(color: _error != null ? X9Colors.error : context.x9.textSecondary)),
        if (lock.biometric) TextButton.icon(onPressed: _bio, icon: const Icon(Icons.fingerprint_rounded), label: const Text('Use fingerprint / face')),
      ] else
        PinPad(length: 4, onCompleted: _submit, error: _error, onBiometric: lock.biometric ? _bio : null),
    ]);
  }
}

/// Full-screen lock shown on app open and after the app was in the background.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked, required this.onForgot, this.appTitle = 'X9'});
  final VoidCallback onUnlocked;
  final VoidCallback onForgot;
  final String appTitle;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (AppLock.instance.biometric && await AppLock.instance.tryBiometric('Unlock ${widget.appTitle}')) widget.onUnlocked();
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = (SessionStore.instance.user?['name'] ?? '').toString();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const X9Logo.mark(height: 64),
              const SizedBox(height: 16),
              Text(name.isEmpty ? 'Welcome back' : 'Hi, ${name.split(' ').first}', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 18),
              UnlockPanel(title: 'Unlock ${widget.appTitle}', onUnlocked: widget.onUnlocked),
              const SizedBox(height: 12),
              TextButton(onPressed: widget.onForgot, child: const Text('Forgot? Sign in again')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// First-run setup: choose PIN or pattern (entered twice) and optionally fingerprint / face.
class LockSetupPage extends StatefulWidget {
  const LockSetupPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<LockSetupPage> createState() => _LockSetupPageState();
}

class _LockSetupPageState extends State<LockSetupPage> {
  LockMethod _method = LockMethod.pin;
  String? _first;
  String? _error;
  bool _bioAvailable = false;
  bool _useBio = true;
  final _pinKey = GlobalKey<PinPadState>();

  @override
  void initState() {
    super.initState();
    AppLock.instance.biometricAvailable().then((v) => mounted ? setState(() => _bioAvailable = v) : null);
  }

  Future<void> _entered(String secret) async {
    if (_first == null) {
      setState(() {
        _first = secret;
        _error = null;
      });
      return;
    }
    if (_first != secret) {
      setState(() {
        _first = null;
        _error = _method == LockMethod.pin ? 'PINs did not match. Start again.' : 'Patterns did not match. Start again.';
      });
      return;
    }
    await AppLock.instance.setUp(_method, secret, useBiometric: _bioAvailable && _useBio);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final what = _method == LockMethod.pin ? '4-digit PIN' : 'pattern (4+ dots)';
    return Scaffold(
      appBar: AppBar(title: const Text('Secure your app')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text('The app and every payment open only after you unlock it on this phone.', textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary)),
            const SizedBox(height: 16),
            SegmentedButton<LockMethod>(
              segments: const [
                ButtonSegment(value: LockMethod.pin, icon: Icon(Icons.pin_rounded), label: Text('PIN')),
                ButtonSegment(value: LockMethod.pattern, icon: Icon(Icons.pattern_rounded), label: Text('Pattern')),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() {
                _method = s.first;
                _first = null;
                _error = null;
              }),
            ),
            const SizedBox(height: 20),
            Text(_first == null ? 'Choose a $what' : 'Enter it again to confirm', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (_method == LockMethod.pin)
              PinPad(key: _pinKey, length: 4, onCompleted: _entered, error: _error)
            else ...[
              PatternLock(onCompleted: _entered, error: _error != null),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: X9Colors.error))),
            ],
            if (_bioAvailable)
              SwitchListTile(
                value: _useBio,
                onChanged: (v) => setState(() => _useBio = v),
                title: const Text('Also unlock with fingerprint / face'),
                secondary: const Icon(Icons.fingerprint_rounded),
              ),
          ]),
        ),
      ),
    );
  }
}
