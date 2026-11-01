import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/google_auth.dart';
import '../../services/signup_location.dart';
import '../../state/app_state.dart';
import '../../util/helpers.dart';
import 'mobile_login_screen.dart';

/// Saves the login from /auth/otp/verify, /auth/google or /auth/google/complete and lets the root gate continue.
Future<void> completeLogin(dynamic response) async {
  final r = asMap(response);
  final token = str(r['token']);
  if (token.isEmpty) throw Exception('Sign-in failed. Please try again.');
  await SessionStore.instance.saveLogin(token, asMap(r['user']));
  AppState.instance.signedIn();
}

/// Opens the sign-up form for a new user (WhatsApp OTP). [mobile] pre-fills the number.
/// The new account always sets its own app lock: any lock left on this phone from a previous account is cleared,
/// so the root gate shows "Secure this device" (PIN / pattern / fingerprint / screen lock) right after sign-up.
void openUserSignup(BuildContext context, {String? mobile}) {
  go(
    context,
    SignupScreen(
      role: SignupRole.user,
      initialMobile: mobile,
      locate: locateForSignup,
      reverseGeocode: reverseGeocodeForSignup,
      onSignedIn: (r) async {
        await AppLock.instance.reset();
        await completeLogin(r);
      },
    ),
  );
}

/// Sign-in found no account for [mobile] (404 SIGNUP_REQUIRED): offer to create one.
Future<void> offerSignup(BuildContext context, String mobile) async {
  final create = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.person_add_alt_1_rounded, color: X9Colors.primary, size: 40),
      title: const Text('No account found'),
      content: const Text('No account for this number. Create one.', textAlign: TextAlign.center),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Create account')),
      ],
    ),
  );
  if (create == true && context.mounted) openUserSignup(context, mobile: mobile);
}

/// First screen: brand hero + "Continue with Google" / "Continue with mobile".
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  bool _googleBusy = false;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      final idToken = await GoogleAuth.instance.signIn();
      if (idToken == null) return;
      final r = asMap(await Api.instance.post('/auth/google', {'id_token': idToken, 'device_id': SessionStore.instance.deviceId}));
      if (asBool(r['need_mobile'])) {
        if (!mounted) return;
        go(
          context,
          MobileLoginScreen(
            googleSignupToken: str(r['signup_token']),
            prefillName: str(r['name']),
            googleEmail: str(r['email']),
          ),
        );
        return;
      }
      await completeLogin(r);
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _a, curve: Curves.easeOut);
    final p = context.x9;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Spacer(),
                    FadeTransition(
                      opacity: fade,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(fade),
                        child: Column(children: [
                          const X9Logo(height: 132),
                          const SizedBox(height: 28),
                          const Eyebrow('Everyday experiences. VIP benefits.', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Text(
                            'Pay. Save. Every day.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Exclusive offers at shops near you, one tap Scan & Pay, the X9 Club wallet and your own prepaid card.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.textSecondary, fontSize: 15, height: 1.45),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                      X9ChipBadge('Up to 30% off', icon: Icons.local_offer_rounded),
                      X9ChipBadge('Scan & Pay', icon: Icons.qr_code_scanner_rounded),
                      X9ChipBadge('Prepaid card', icon: Icons.credit_card_rounded),
                    ]),
                    const Spacer(),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () => go(context, const MobileLoginScreen()),
                      icon: const Icon(Icons.phone_iphone_rounded),
                      label: const Text('Continue with mobile'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _googleBusy ? null : _google,
                      child: _googleBusy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                              _GoogleG(),
                              SizedBox(width: 12),
                              Text('Continue with Google'),
                            ]),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => openUserSignup(context),
                      child: const Text('New to X9? Create account'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'By continuing you agree to the X9 terms and privacy policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple "G" mark drawn with text (no image assets needed). Google brand blue is kept as the
/// third-party sign-in mark; it is not part of the X9 palette.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.x9.border)),
        child: const Text('G', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w600, fontSize: 16)),
      );
}
