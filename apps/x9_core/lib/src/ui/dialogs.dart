import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../bootstrap.dart';
import 'theme.dart';

// =====================================================================================================================
// v6.13 - one place for every confirmation and every error pop-up of all X9 apps.
//   * confirmAction()           Cancel / OK pop-up (payment, invoice, banner / video, partner / merchant, prepaid card, changes)
//   * Api.confirmPrompt         asks automatically before any change call (see Api._guard); screens that already asked call
//                               Api.instance.markConfirmed() so the person is not asked twice
//   * classifyError()/showErrorDialog()   low balance, user not valid, server down, settlement failed (+ Contact support)
// =====================================================================================================================

/// Cancel / OK confirmation pop-up. Returns true on OK. An accepted confirmation also covers the next change call
/// ([Api.markConfirmed]), so the same action is never asked twice.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool danger = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: Icon(icon, color: danger ? X9Colors.error : X9Colors.primary, size: 36),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(cancelLabel)),
        FilledButton(
          onPressed: () => Navigator.pop(d, true),
          style: FilledButton.styleFrom(minimumSize: const Size(110, 44), backgroundColor: danger ? X9Colors.error : null),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  if (ok == true) Api.instance.markConfirmed();
  return ok == true;
}

/// The words of the automatic confirmation for a request.
class ConfirmCopy {
  const ConfirmCopy(this.title, this.message, {this.danger = false, this.icon = Icons.help_outline_rounded});
  final String title;
  final String message;
  final bool danger;
  final IconData icon;
}

ConfirmCopy confirmCopyFor(String method, String path) {
  final p = path.split('?').first.toLowerCase();
  bool has(String s) => p.contains(s);
  if (has('/cancel') || has('/reject') || has('/revoke')) {
    return const ConfirmCopy('Cancel this?', 'Do you want to cancel this? It cannot be undone.', danger: true, icon: Icons.cancel_outlined);
  }
  if (has('/bills') || has('/invoices')) {
    return const ConfirmCopy('Create invoice', 'Create this invoice? The customer can pay it as soon as it is created.', icon: Icons.receipt_long_rounded);
  }
  if (has('/ads') || has('/banners') || has('/advertisements') || has('/playlist')) {
    return const ConfirmCopy('Publish banner / video', 'Send this banner or video for publishing? It goes live for the selected audience.', icon: Icons.campaign_rounded);
  }
  if (has('/orders')) {
    return const ConfirmCopy('Place order', 'Send this order to the shop?', icon: Icons.shopping_bag_rounded);
  }
  if (has('/appointments')) {
    return const ConfirmCopy('Appointment', 'Send this appointment request?', icon: Icons.event_available_rounded);
  }
  if (has('/promotions')) {
    return const ConfirmCopy('Offer', 'Save or publish this offer? Customers see it once it is live.', icon: Icons.local_offer_rounded);
  }
  if (has('/cards')) {
    return const ConfirmCopy('Prepaid card', 'Confirm this prepaid card request?', icon: Icons.credit_card_rounded);
  }
  if (has('/kyc')) {
    return const ConfirmCopy('Submit KYC', 'Submit these KYC documents? Check the numbers and pictures first.', icon: Icons.verified_user_rounded);
  }
  if (has('/partners') || has('/merchants') || has('/freelancers') || has('/staff')) {
    return const ConfirmCopy('Add partner / merchant', 'Add this partner or merchant? They will be able to sign in to X9.', icon: Icons.person_add_alt_1_rounded);
  }
  if (has('/pay') || has('/payments') || has('/payouts') || has('/settlement') || has('/transfer') || has('/payment-links') || has('/wallet') || has('/vip/purchase') || has('/adjust')) {
    return const ConfirmCopy('Confirm payment', 'Do you want to go ahead with this payment or transfer?', icon: Icons.payments_rounded);
  }
  if (method == 'DELETE') {
    return const ConfirmCopy('Delete this?', 'This will be deleted and cannot be undone.', danger: true, icon: Icons.delete_outline_rounded);
  }
  return const ConfirmCopy('Confirm changes', 'Do you want to save these changes?', icon: Icons.edit_note_rounded);
}

/// Registered as [Api.confirmPrompt] by [runX9App].
Future<bool> showConfirmForRequest(String method, String path) async {
  final nav = X9Bootstrap.navigatorKey?.currentState;
  final ctx = nav?.overlay?.context ?? X9Bootstrap.navigatorKey?.currentContext;
  if (ctx == null || !ctx.mounted) return true; // no screen to ask on (background work): go ahead
  final c = confirmCopyFor(method, path);
  return confirmAction(ctx, title: c.title, message: c.message, danger: c.danger, icon: c.icon);
}

// =====================================================================================================================
// Errors
// =====================================================================================================================

enum X9ErrorKind { lowBalance, userInvalid, serverDown, settlement }

class X9ErrorInfo {
  const X9ErrorInfo(this.kind, this.title, this.message);
  final X9ErrorKind kind;
  final String title;
  final String message;
}

/// Support contacts: set by the admin (Super Admin > App settings > Support) and read from GET /support;
/// build-time values (--dart-define=SUPPORT_PHONE / SUPPORT_EMAIL / SUPPORT_WHATSAPP) are the fallback.
class SupportContact {
  static String phone = const String.fromEnvironment('SUPPORT_PHONE', defaultValue: '');
  static String email = const String.fromEnvironment('SUPPORT_EMAIL', defaultValue: '');
  static String whatsapp = const String.fromEnvironment('SUPPORT_WHATSAPP', defaultValue: '');
  static bool _loaded = false;

  static bool get any => phone.isNotEmpty || email.isNotEmpty || whatsapp.isNotEmpty;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final r = await Api.instance.get('/support').timeout(const Duration(seconds: 4));
      if (r is Map) {
        phone = (r['phone'] ?? '').toString().isNotEmpty ? r['phone'].toString() : phone;
        email = (r['email'] ?? '').toString().isNotEmpty ? r['email'].toString() : email;
        whatsapp = (r['whatsapp'] ?? '').toString().isNotEmpty ? r['whatsapp'].toString() : whatsapp;
        _loaded = true;
      }
    } catch (_) {/* offline or server down: use what we have */}
  }
}

/// Maps an API error to one of the four pop-up kinds, or null for ordinary messages (shown as a snack bar).
X9ErrorInfo? classifyError(Object e) {
  if (e is! ApiException) return null;
  if (e.code == 'CANCELLED') return null;
  final code = (e.code ?? '').toUpperCase();
  final msg = e.message.toLowerCase();
  if (code.startsWith('SETTLEMENT') || code.startsWith('PAYOUT') || msg.contains('settlement')) {
    return describeSettlementFailure(e.display);
  }
  if (const {'INSUFFICIENT_FUNDS', 'INSUFFICIENT_BALANCE', 'INSUFFICIENT_MERCHANT_BALANCE'}.contains(code) || msg.contains('insufficient') || msg.contains('low balance')) {
    final merchant = code == 'INSUFFICIENT_MERCHANT_BALANCE';
    return X9ErrorInfo(
      X9ErrorKind.lowBalance,
      'Low balance',
      '${merchant ? 'Your merchant wallet' : 'Your wallet'} does not have enough money for this. '
          '${merchant ? 'Wait for more sales to be credited, or ask support.' : 'Add money to your X9 wallet and try again.'}',
    );
  }
  if (const {'USER_NOT_FOUND', 'RECIPIENT_NOT_FOUND', 'USER_INACTIVE', 'USER_BLOCKED', 'USER_SUSPENDED'}.contains(code) || msg.contains('not an x9 user') || msg.contains('user not found') || msg.contains('recipient not found')) {
    return const X9ErrorInfo(X9ErrorKind.userInvalid, 'User not valid',
        'This mobile number is not an active X9 user. Check the number and try again, or ask the person to sign up on X9 first.');
  }
  if (e.status == 0 || e.status >= 500 || code == 'TIMEOUT') {
    return X9ErrorInfo(
      X9ErrorKind.serverDown,
      e.status >= 500 ? 'Something went wrong on our side' : 'Server not reachable',
      e.status >= 500
          ? 'X9 had a problem and could not finish this. Nothing was lost. Wait a minute and try again. If it keeps happening, contact support.'
          : 'We could not reach the X9 server. Check your internet connection, wait a minute and try again. If it keeps happening, the server may be down for maintenance: contact support.',
    );
  }
  return null;
}

/// A failed settlement / payout: what the reason means, what to do, and who to ask.
X9ErrorInfo describeSettlementFailure(String? reason) {
  final r = (reason ?? '').trim();
  final l = r.toLowerCase();
  String cause;
  String action;
  bool has(List<String> words) => words.any(l.contains);
  if (has(['ifsc'])) {
    cause = 'The IFSC code of your bank account is not valid.';
    action = 'Open Settlement > Bank accounts, correct the IFSC code and request the settlement again.';
  } else if (has(['name mismatch', 'beneficiary name', 'holder name', 'name does not'])) {
    cause = 'The account holder name does not match the name registered with the bank.';
    action = 'Add the bank account again with the name exactly as on your bank passbook.';
  } else if (has(['account number', 'invalid account', 'no such account', 'does not exist', 'closed', 'frozen', 'dormant', 'blocked account'])) {
    cause = 'The bank could not find or use this account (wrong number, or the account is closed, frozen or dormant).';
    action = 'Check the account number with your bank, add the correct account and try again.';
  } else if (has(['not verified', 'unverified', 'verification pending', 'beneficiary'])) {
    cause = 'This bank account is not verified yet.';
    action = 'X9 verifies a new bank account first, usually within one working day. Try again after it shows Verified.';
  } else if (has(['insufficient', 'balance', 'fee'])) {
    cause = 'Your wallet balance could not cover the amount plus the settlement fee.';
    action = 'Request a smaller amount, or wait until more payments are credited.';
  } else if (has(['limit', 'exceed', 'maximum', 'minimum', 'too small', 'too large'])) {
    cause = 'The amount is outside the limit allowed for a settlement.';
    action = 'Change the amount and try again.';
  } else if (has(['kyc'])) {
    cause = 'Your KYC is not complete, so settlements are on hold.';
    action = 'Complete or correct your KYC. Support can tell you what is missing.';
  } else if (has(['timeout', 'timed out', 'bank down', 'technical', 'unavailable', 'server', 'network', 'issuer', 'gateway', 'switch'])) {
    cause = 'The bank or the payment network was not available.';
    action = 'This is usually temporary. The money is back in your wallet; try again after some time.';
  } else if (r.isEmpty) {
    cause = 'The settlement could not be completed.';
    action = 'The money is back in your wallet. Try again; if it fails again, contact support.';
  } else {
    cause = 'Reason given: $r';
    action = 'The money is back in your wallet. Check the bank details and try again.';
  }
  return X9ErrorInfo(X9ErrorKind.settlement, 'Settlement failed', '$cause\n\nWhat to do: $action\n\nStill stuck? Contact support and quote the settlement reference.');
}

IconData _iconFor(X9ErrorKind k) => switch (k) {
      X9ErrorKind.lowBalance => Icons.account_balance_wallet_outlined,
      X9ErrorKind.userInvalid => Icons.person_off_outlined,
      X9ErrorKind.serverDown => Icons.cloud_off_rounded,
      X9ErrorKind.settlement => Icons.account_balance_rounded,
    };

Future<void> _open(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Error pop-up with OK and the support contacts (call / WhatsApp / e-mail).
Future<void> showErrorDialog(BuildContext context, Object e, {X9ErrorInfo? info}) async {
  final i = info ?? classifyError(e);
  if (i == null) return;
  unawaited(SupportContact.load());
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      icon: Icon(_iconFor(i.kind), color: X9Colors.error, size: 38),
      title: Text(i.title, textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(i.message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          _SupportButtons(),
        ]),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(d), style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), child: const Text('OK')),
      ],
      actionsAlignment: MainAxisAlignment.center,
    ),
  );
}

class _SupportButtons extends StatefulWidget {
  @override
  State<_SupportButtons> createState() => _SupportButtonsState();
}

class _SupportButtonsState extends State<_SupportButtons> {
  @override
  void initState() {
    super.initState();
    // the contacts may arrive a moment after the pop-up opens
    SupportContact.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SupportContact.any) {
      return Text('Contact X9 support for help.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall);
    }
    final digits = SupportContact.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
      if (SupportContact.phone.isNotEmpty)
        OutlinedButton.icon(onPressed: () => _open('tel:${SupportContact.phone}'), icon: const Icon(Icons.call_rounded, size: 18), label: const Text('Call support'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40))),
      if (digits.isNotEmpty)
        OutlinedButton.icon(onPressed: () => _open('https://wa.me/$digits'), icon: const Icon(Icons.chat_rounded, size: 18), label: const Text('WhatsApp'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40))),
      if (SupportContact.email.isNotEmpty)
        OutlinedButton.icon(onPressed: () => _open('mailto:${SupportContact.email}'), icon: const Icon(Icons.mail_outline_rounded, size: 18), label: const Text('E-mail'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40))),
    ]);
  }
}
