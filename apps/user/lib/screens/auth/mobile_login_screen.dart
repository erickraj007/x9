import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import 'otp_screen.dart';
import 'welcome_screen.dart';

/// Mobile (+91), optional e-mail and name → POST /auth/otp/request → OTP screen.
/// With [googleSignupToken] it is the "add your mobile" step of a new Google sign-up.
class MobileLoginScreen extends StatefulWidget {
  const MobileLoginScreen({super.key, this.googleSignupToken, this.prefillName, this.googleEmail});
  final String? googleSignupToken;
  final String? prefillName;
  final String? googleEmail;

  @override
  State<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends State<MobileLoginScreen> {
  final _mobile = TextEditingController();
  late final _name = TextEditingController(text: widget.prefillName ?? '');
  final _email = TextEditingController();
  bool _more = false;
  String? _error;

  bool get _google => (widget.googleSignupToken ?? '').isNotEmpty;

  @override
  void dispose() {
    _mobile.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final m = _mobile.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(m)) {
      setState(() => _error = 'Enter a valid 10-digit mobile number');
      return;
    }
    final email = _google ? '' : _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw Exception('Enter a valid e-mail address or leave it empty.');
    }
    setState(() => _error = null);
    Map<String, dynamic> r;
    try {
      r = asMap(await Api.instance.post('/auth/otp/request', {'mobile': m, if (email.isNotEmpty) 'email': email}));
    } on ApiException catch (e) {
      if (e.code == 'SIGNUP_REQUIRED' && !_google) {
        if (mounted) await offerSignup(context, m);
        return;
      }
      rethrow;
    }
    if (!mounted) return;
    go(
      context,
      OtpScreen(
        mobile: m,
        email: email.isEmpty ? null : email,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        smsLength: asInt(r['length']) > 0 ? asInt(r['length']) : 5,
        emailSent: email.isNotEmpty && (r['email_sent'] == null || asBool(r['email_sent'])),
        emailLength: asInt(r['email_length']) > 0 ? asInt(r['email_length']) : 6,
        googleSignupToken: widget.googleSignupToken,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
          const Center(child: X9Logo(height: 92)),
          const SizedBox(height: 16),
          Text(_google ? 'Add your mobile' : 'Enter your mobile number', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            _google
                ? 'Your Google account ${widget.googleEmail ?? ''} is almost set up. Verify your mobile to finish.'
                : 'We will send a one-time password (OTP) to verify it. New to X9? This creates your account.',
            style: TextStyle(color: context.x9.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _mobile,
            autofocus: true,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.5),
            decoration: InputDecoration(
              labelText: 'Mobile number',
              counterText: '',
              errorText: _error,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 16, right: 8),
                child: Text('🇮🇳  +91', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
            onSubmitted: (_) => _continue().catchError((Object e) {
              if (mounted) showFriendlyError(context, e);
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Your name (for new accounts)', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          if (!_google) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _more = !_more),
                icon: Icon(_more ? Icons.remove_rounded : Icons.add_rounded, size: 18),
                label: Text(_more ? 'No e-mail' : 'Add e-mail (optional)'),
              ),
            ),
            if (_more)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.alternate_email_rounded), helperText: 'We will verify it with a 6-digit e-mail OTP'),
              ),
          ],
          const SizedBox(height: 28),
          BusyButton(label: 'Get OTP', icon: Icons.sms_rounded, onPressed: _continue),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PasswordSignInScreen(deviceName: 'X9 app', onSignedIn: completeLogin),
            )),
            child: const Text('Sign in with password / Forgot password?'),
          ),
        ]),
      ),
    );
  }
}
