import 'package:flutter/material.dart';

import '../api.dart';
import 'logo.dart';
import 'otp_boxes.dart';
import 'theme.dart';

String _msg(Object e) => e is ApiException ? e.display : 'Could not reach X9. Check your internet connection and try again.';

String? _cleanMobile(String v) {
  final d = v.replaceAll(RegExp(r'\D'), '');
  final t = d.length > 10 ? d.substring(d.length - 10) : d;
  return RegExp(r'^[6-9]\d{9}$').hasMatch(t) ? t : null;
}

/// Forgot password, shared by every X9 app:
/// 1. registered mobile number or e-mail -> a WhatsApp OTP (and a reset link to the sign-up e-mail),
/// 2. OTP + new password + confirm password,
/// 3. "Password changed" -> back to sign in.
/// Pops with `true` when the password was changed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialLogin = ''});
  final String initialLogin;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _login = TextEditingController(text: widget.initialLogin);
  final _otp = TextEditingController();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  int _step = 0;
  bool _busy = false;
  bool _hide = true;
  String? _error;
  String _token = '';
  int _len = 5;
  String _sentTo = '';
  bool _emailSent = false;

  @override
  void dispose() {
    _login.dispose();
    _otp.dispose();
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _login.text.trim();
    final v = t.contains('@') ? t.toLowerCase() : (_cleanMobile(t) ?? '');
    if (v.isEmpty || (t.contains('@') && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v))) {
      setState(() => _error = 'Enter your registered 10-digit mobile number or e-mail.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.instance.post('/auth/password/forgot', {'login': v});
      final m = r is Map ? r : const {};
      if (!mounted) return;
      setState(() {
        _token = '${m['reset_token'] ?? ''}';
        _len = int.tryParse('${m['otp_length'] ?? ''}') ?? 5;
        _sentTo = '${m['otp_sent_to'] ?? ''}';
        _emailSent = m['email_link_sent'] == true;
        _otp.clear();
        _step = 1;
        _busy = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = _msg(e);
      });
    }
  }

  Future<void> _reset() async {
    if (_otp.text.trim().length < 4) {
      setState(() => _error = 'Enter the OTP.');
      return;
    }
    if (_p1.text.length < 8) {
      setState(() => _error = 'The new password needs at least 8 characters.');
      return;
    }
    if (_p1.text != _p2.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.post('/auth/password/reset', {
        'reset_token': _token,
        'otp': _otp.text.trim(),
        'password': _p1.text,
        'password_confirmation': _p2.text,
      });
      if (mounted) setState(() {
        _busy = false;
        _step = 2;
      });
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = _msg(e);
        if (e is ApiException && (e.code == 'OTP_INVALID' || e.code == 'OTP_LOCKED')) _otp.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password'), leading: _step == 2 ? const SizedBox.shrink() : null),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 32), children: [
          const Center(child: X9Logo(height: 84)),
          const SizedBox(height: 22),
          if (_step == 0) ..._stepLogin(p),
          if (_step == 1) ..._stepReset(p),
          if (_step == 2) ..._stepDone(p),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  List<Widget> _stepLogin(X9Palette p) => [
        Text('Reset your password', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Enter the mobile number or e-mail you signed up with. We send a WhatsApp OTP to your mobile and a reset link to your e-mail.',
          style: TextStyle(color: p.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _login,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          onSubmitted: (_) => _send(),
          decoration: const InputDecoration(labelText: 'Mobile number or e-mail', prefixIcon: Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Send OTP / reset link'),
        ),
      ];

  List<Widget> _stepReset(X9Palette p) => [
        Text('Enter OTP and new password', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          [
            if (_sentTo.isNotEmpty) 'We sent a WhatsApp OTP to $_sentTo.',
            if (_emailSent) 'A reset link was also e-mailed to you: you can open it instead and set the password there.',
          ].join(' '),
          style: TextStyle(color: p.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 20),
        X9OtpBoxes(length: _len, controller: _otp, autofocus: true),
        const SizedBox(height: 18),
        TextField(
          controller: _p1,
          obscureText: _hide,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New password',
            helperText: 'At least 8 characters',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _hide = !_hide)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _p2,
          obscureText: _hide,
          onSubmitted: (_) => _reset(),
          decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_reset_rounded)),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _reset,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Set new password'),
        ),
        TextButton(onPressed: _busy ? null : () => setState(() { _step = 0; _error = null; }), child: const Text('Use a different number / e-mail')),
      ];

  List<Widget> _stepDone(X9Palette p) => [
        const Icon(Icons.check_circle_rounded, size: 72, color: Color(0xFF1E7D3A)),
        const SizedBox(height: 14),
        Text('Password changed', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('You were signed out of all devices. Sign in with your new password.', textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary, height: 1.45)),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Back to sign in')),
      ];
}

/// Password sign-in for the customer app (mobile or e-mail + password -> WhatsApp OTP -> signed in), with the
/// "Forgot password?" link. [onSignedIn] gets the `/auth/login/otp` answer ({token, user}).
class PasswordSignInScreen extends StatefulWidget {
  const PasswordSignInScreen({super.key, required this.deviceName, required this.onSignedIn});
  final String deviceName;
  final Future<void> Function(Map<String, dynamic> response) onSignedIn;

  @override
  State<PasswordSignInScreen> createState() => _PasswordSignInScreenState();
}

class _PasswordSignInScreenState extends State<PasswordSignInScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;
  String? _info;
  String _otpToken = '';
  int _len = 5;
  String _sentTo = '';

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _loginValue {
    final t = _login.text.trim();
    return t.contains('@') ? t.toLowerCase() : (_cleanMobile(t) ?? t);
  }

  Future<void> _next() async {
    if (_loginValue.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your mobile / e-mail and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final r = await Api.instance.post('/auth/login', {'login': _loginValue, 'password': _password.text, 'device_name': widget.deviceName});
      final m = r is Map ? r : const {};
      if (!mounted) return;
      setState(() {
        _otpToken = '${m['otp_token'] ?? ''}';
        _len = int.tryParse('${m['otp_length'] ?? ''}') ?? 5;
        _sentTo = '${m['otp_sent_to'] ?? ''}';
        _busy = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e is ApiException && e.code == 'INVALID_CREDENTIALS' ? 'Wrong mobile / e-mail or password. Use "Forgot password?" if you have not set one.' : _msg(e);
      });
    }
  }

  Future<void> _verify() async {
    if (_otp.text.trim().length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.instance.post('/auth/login/otp', {'otp_token': _otpToken, 'otp': _otp.text.trim()});
      await widget.onSignedIn(r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{});
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = _msg(e);
        _otp.clear();
      });
    }
  }

  Future<void> _forgot() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => ForgotPasswordScreen(initialLogin: _login.text.trim())));
    if (changed == true && mounted) {
      setState(() {
        _password.clear();
        _info = 'Password changed. Sign in with your new password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final otpStep = _otpToken.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with password')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 32), children: [
          const Center(child: X9Logo(height: 84)),
          const SizedBox(height: 22),
          if (!otpStep) ...[
            TextField(controller: _login, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Mobile number or e-mail', prefixIcon: Icon(Icons.person_outline_rounded))),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _hide,
              onSubmitted: (_) => _next(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _hide = !_hide)),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _next,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Continue'),
            ),
            TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password? / Create new password')),
          ] else ...[
            Text('Enter the WhatsApp OTP sent to $_sentTo', textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
            const SizedBox(height: 18),
            X9OtpBoxes(length: _len, controller: _otp, autofocus: true, onCompleted: (_) => _verify()),
            const SizedBox(height: 22),
            FilledButton(onPressed: _busy ? null : _verify, child: const Text('Verify & sign in')),
            TextButton(onPressed: _busy ? null : () => setState(() { _otpToken = ''; _otp.clear(); }), child: const Text('Back')),
          ],
          if (_info != null) ...[const SizedBox(height: 14), Text(_info!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF1E7D3A), fontWeight: FontWeight.w600))],
          if (_error != null) ...[const SizedBox(height: 14), Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w600))],
        ]),
      ),
    );
  }
}
