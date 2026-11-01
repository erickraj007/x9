import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../state/kyc_state.dart';
import '../kyc/kyc_entry.dart';

/// Security: change PIN / pattern (verify current first), fingerprint / face toggle, device approval.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    AppLock.instance.biometricAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  Future<bool> _verifyCurrent(String title) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (c) => _VerifyPage(title: title)));
    return ok == true;
  }

  Future<void> _changeLock() async {
    if (!await _verifyCurrent('Enter your current ${AppLock.instance.method == LockMethod.pattern ? 'pattern' : 'PIN'}')) return;
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (c) => LockSetupPage(onDone: () {
        Navigator.of(c).pop();
      }),
    ));
    if (!mounted) return;
    setState(() {});
    showOk(context, 'App lock updated');
  }

  Future<void> _toggleBio(bool v) async {
    if (v) {
      // prove the fingerprint / face works before turning it on
      AppLock.instance.biometric = true;
      final ok = await AppLock.instance.tryBiometric('Turn on fingerprint / face unlock');
      if (!ok) {
        AppLock.instance.biometric = false;
        if (mounted) showError(context, 'Fingerprint / face was not confirmed.');
        return;
      }
    } else {
      if (!await _verifyCurrent('Confirm to turn off fingerprint / face')) return;
      AppLock.instance.biometric = false;
    }
    await SessionStore.instance.write('lock_biometric', v ? '1' : '0');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    final method = lock.method == LockMethod.pattern ? 'Pattern' : 'PIN';
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(22)),
          child: const Row(children: [
            Icon(Icons.shield_rounded, color: Colors.white, size: 40),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'X9 opens and approves every payment only after you unlock it on this phone.',
                style: TextStyle(color: Colors.white, height: 1.35, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(lock.method == LockMethod.pattern ? Icons.pattern_rounded : Icons.pin_rounded, color: X9Colors.primary),
              title: Text('Change $method / switch method'),
              subtitle: Text('Current app lock: $method'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _changeLock,
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded, color: X9Colors.primary),
              title: const Text('Fingerprint / face unlock'),
              subtitle: Text(_bioAvailable ? 'Use your phone\'s biometrics' : 'Not available on this phone'),
              value: lock.biometric,
              onChanged: _bioAvailable ? _toggleBio : null,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListenableBuilder(
              listenable: KycState.instance,
              builder: (context, _) => ListTile(
                leading: const Icon(Icons.verified_user_rounded, color: X9Colors.primary),
                title: const Text('KYC verification'),
                subtitle: Text(KycState.instance.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openKyc(context),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.phonelink_lock_rounded, color: X9Colors.success),
              title: const Text('Payment approval'),
              subtitle: const Text('This phone signs every payment with its own key, kept in Android secure storage.'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: X9Colors.error),
              title: const Text('Sign out and remove this phone'),
              subtitle: const Text('Use this if you are giving the phone to someone else.'),
              onTap: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text('This phone will no longer be able to approve payments until you sign in again.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sign out')),
                    ],
                  ),
                );
                if (sure == true) await AppState.instance.signOut();
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(
          'X9 never asks for your PIN, card PIN, CVV or OTP on a call or message.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5),
        ),
      ]),
    );
  }
}

class _VerifyPage extends StatelessWidget {
  const _VerifyPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    var done = false;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify it\'s you')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: UnlockPanel(
              title: title,
              onUnlocked: () {
                if (done) return;
                done = true;
                Navigator.of(context).pop(true);
              },
            ),
          ),
        ),
      ),
    );
  }
}
