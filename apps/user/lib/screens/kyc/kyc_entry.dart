import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/image_pick.dart';
import '../../state/kyc_state.dart';

/// The KYC screen wired to the photo picker and the cached KYC state.
Widget kycScreen() => UserKycScreen(pickImage: pickKycImage, onChanged: KycState.instance.setInfo);

/// Opens the KYC screen (status + upload form) and refreshes the cached status when it closes.
Future<void> openKyc(BuildContext context) async {
  await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => kycScreen()));
  await KycState.instance.load(force: true);
}

/// Dialog "Complete KYC to use wallet, prepaid card and banking" (shown for 403 KYC_REQUIRED).
Future<void> showKycGate(BuildContext context) =>
    KycGate.show(context, pickImage: pickKycImage, onChanged: KycState.instance.setInfo);

/// In-page version of the same message with the "Complete KYC" button.
class UserKycGate extends StatelessWidget {
  const UserKycGate({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: KycGate(pickImage: pickKycImage, onChanged: KycState.instance.setInfo),
      );
}

/// Compact banner for the home screen; hidden when KYC is verified or the status is not known yet.
class HomeKycBanner extends StatelessWidget {
  const HomeKycBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KycState.instance,
      builder: (context, _) {
        final k = KycState.instance;
        if (!k.needsKyc) return const SizedBox.shrink();
        final s = k.status;
        final submitted = s == 'SUBMITTED';
        final rejected = s == 'REJECTED';
        final title = submitted
            ? 'KYC submitted - under review'
            : rejected
                ? 'KYC rejected - submit again'
                : 'Complete KYC';
        final sub = submitted ? 'We will message you once it is verified.' : 'Needed to use wallet, prepaid card and banking.';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: context.x9.primarySoft,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              leading: Icon(submitted ? Icons.schedule_rounded : Icons.verified_user_rounded, color: X9Colors.primary),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(sub),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => openKyc(context),
            ),
          ),
        );
      },
    );
  }
}
