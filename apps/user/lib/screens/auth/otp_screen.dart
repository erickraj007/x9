import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../widgets/otp_boxes.dart';
import 'welcome_screen.dart';

/// SMS OTP (5 digits) plus the e-mail OTP (6 digits) when an e-mail was given.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.mobile,
    this.email,
    this.name,
    this.smsLength = 5,
    this.emailSent = false,
    this.emailLength = 6,
    this.googleSignupToken,
  });

  final String mobile;
  final String? email;
  final String? name;
  final int smsLength;
  final bool emailSent;
  final int emailLength;
  final String? googleSignupToken;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _sms = TextEditingController();
  final _mail = TextEditingController();
  bool _busy = false;

  bool get _needEmail => widget.email != null && widget.emailSent;
  bool get _google => (widget.googleSignupToken ?? '').isNotEmpty;

  @override
  void dispose() {
    _sms.dispose();
    _mail.dispose();
    super.dispose();
  }

  bool get _ready => _sms.text.length == widget.smsLength && (!_needEmail || _mail.text.length == widget.emailLength);

  Future<void> _verify() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    try {
      final deviceId = SessionStore.instance.deviceId;
      final r = _google
          ? await Api.instance.post('/auth/google/complete', {
              'signup_token': widget.googleSignupToken,
              'mobile': widget.mobile,
              'otp': _sms.text,
              'device_id': deviceId,
            })
          : await Api.instance.post('/auth/otp/verify', {
              'mobile': widget.mobile,
              'otp': _sms.text,
              if (widget.email != null) 'email': widget.email,
              if (_needEmail) 'email_otp': _mail.text,
              if (widget.name != null) 'name': widget.name,
              'device_id': deviceId,
            });
      await completeLogin(r);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'SIGNUP_REQUIRED' && !_google) {
        setState(() => _busy = false);
        await offerSignup(context, widget.mobile);
        return;
      }
      showError(context, e);
      setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    await Api.instance.post('/auth/otp/request', {'mobile': widget.mobile, if (widget.email != null && !_google) 'email': widget.email});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
          const Center(child: X9Logo(height: 92)),
          const SizedBox(height: 16),
          Text('Verify OTP', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Enter the code sent on WhatsApp to '),
              TextSpan(text: '+91 ${widget.mobile}', style: TextStyle(fontWeight: FontWeight.w600, color: context.x9.text)),
            ]),
            style: TextStyle(color: context.x9.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 26),
          OtpBoxes(
            length: widget.smsLength,
            controller: _sms,
            autofocus: true,
            onCompleted: (_) {
              setState(() {});
              if (_ready) _verify();
            },
          ),
          if (_needEmail) ...[
            const SizedBox(height: 26),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'E-mail code sent to '),
                TextSpan(text: widget.email, style: TextStyle(fontWeight: FontWeight.w600, color: context.x9.text)),
              ]),
              style: TextStyle(color: context.x9.textSecondary),
            ),
            const SizedBox(height: 12),
            OtpBoxes(
              length: widget.emailLength,
              controller: _mail,
              onCompleted: (_) {
                setState(() {});
                if (_ready) _verify();
              },
            ),
          ],
          const SizedBox(height: 22),
          Center(child: ResendTimer(onResend: _resend)),
          const SizedBox(height: 22),
          ListenableBuilder(
            listenable: Listenable.merge([_sms, _mail]),
            builder: (context, _) => FilledButton(
              onPressed: _ready && !_busy ? _verify : null,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Verify & continue'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Change mobile number')),
        ]),
      ),
    );
  }
}
