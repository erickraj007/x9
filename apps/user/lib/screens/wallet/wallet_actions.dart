import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/amount_entry.dart';
import '../../widgets/result_screen.dart';
import '../card/card_screen.dart';
import 'bank_transfer_screen.dart';
import 'load_wallet_screen.dart';

/// X9 Club wallet → anywhere (POST /app/wallet/pay). Runs from the amount screen's [ctx]:
/// review sheet → phone unlock → signed money call → result screen (replaces the amount screen).
Future<void> walletPay(
  BuildContext ctx, {
  required int amount,
  required Map<String, dynamic> body,
  required String title,
  required String resultTitle,
  List<MapEntry<String, String>> rows = const [],
}) async {
  final review = await showReviewSheet(
    ctx,
    title: title,
    amount: amount,
    rows: [const MapEntry('From', 'X9 Club wallet'), ...rows],
    confirmLabel: 'Pay ${money(amount)}',
  );
  if (!review || !ctx.mounted) return;
  final unlocked = await AppLock.instance.confirm(ctx, reason: 'Pay ${money(amount)}');
  if (!unlocked || !ctx.mounted) return;
  final r = asMap(await Api.instance.money('POST', '/app/wallet/pay', {...body, 'amount': amount}, amount: amount));
  AppState.instance.refreshBalances();
  if (!ctx.mounted) return;
  final status = str(r['status'], 'SUCCESS').toUpperCase();
  String? msg;
  if (status == 'FAILED') {
    msg = str(r['failure_reason'], 'The transfer could not be completed. No money was taken.');
  } else if (status == 'REQUESTED' || status == 'PENDING') {
    msg = 'Your request is being processed. The money reaches the account once the bank confirms it.';
  }
  Navigator.of(ctx).pushReplacement(MaterialPageRoute<void>(
    builder: (_) => ResultScreen(status: status, title: resultTitle, amount: amount, message: msg, reference: str(r['reference']), details: rows),
  ));
}

/// Transfer chooser (home quick action).
Future<void> showTransferSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (c) {
      Widget tile(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: Colors.white),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(c);
              onTap();
            },
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Send money', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          tile(Icons.person_rounded, 'To X9 user', 'Instant, to any X9 mobile number', () => startToUser(context)),
          tile(Icons.account_balance_rounded, 'To bank / UPI ID', 'Withdraw to your bank account or UPI', () => startToBank(context)),
          tile(Icons.credit_card_rounded, 'To prepaid card', 'Top up your X9 prepaid card', () => startToCard(context)),
          tile(Icons.add_card_rounded, 'Add money', 'Load your X9 wallet with any UPI app', () => startLoadWallet(context)),
          const SizedBox(height: 12),
        ]),
      );
    },
  );
}

/// USR > USR
Future<void> startToUser(BuildContext context, {String? mobile}) async {
  final m = mobile ?? await _askMobile(context);
  if (m == null || !context.mounted) return;
  go(
    context,
    AmountEntryScreen(
      title: 'Send to X9 user',
      recipient: RecipientHeader(icon: Icons.person_rounded, title: fmtMobile(m), subtitle: 'X9 user · instant transfer'),
      available: AppState.instance.knownClubBalance,
      actionLabel: 'Review',
      onSubmit: (ctx, paise) => walletPay(
        ctx,
        amount: paise,
        body: {'to_type': 'USR', 'to': m},
        title: 'Send to ${fmtMobile(m)}',
        resultTitle: 'Sent to ${fmtMobile(m)}',
        rows: [MapEntry('To', fmtMobile(m))],
      ),
    ),
  );
}

/// USR > PRWC (X9 Club wallet → prepaid card)
Future<void> startToCard(BuildContext context, {Map<String, dynamic>? card}) async {
  Map<String, dynamic>? c = card;
  if (c == null) {
    List<Map<String, dynamic>> cards;
    try {
      cards = await withProgress(context, activeCards);
    } catch (e) {
      if (context.mounted) showFriendlyError(context, e);
      return;
    }
    if (!context.mounted) return;
    if (cards.isEmpty) {
      showError(context, 'You do not have an active prepaid card yet.');
      go(context, const CardScreen());
      return;
    }
    c = cards.length == 1 ? cards.first : await pickCard(context, cards);
  }
  if (c == null || !context.mounted) return;
  final cardId = asInt(c['id']);
  final masked = str(c['masked_number'], 'X9 prepaid card');
  go(
    context,
    AmountEntryScreen(
      title: 'Add to prepaid card',
      recipient: RecipientHeader(icon: Icons.credit_card_rounded, title: 'X9 prepaid card', subtitle: masked),
      available: AppState.instance.knownClubBalance,
      actionLabel: 'Review',
      onSubmit: (ctx, paise) => walletPay(
        ctx,
        amount: paise,
        body: {'to_type': 'PRWC', 'card_id': cardId},
        title: 'Add to prepaid card',
        resultTitle: 'Added to prepaid card',
        rows: [MapEntry('To card', masked)],
      ),
    ),
  );
}

/// USR > PAYOUT (bank account or UPI ID)
void startToBank(BuildContext context) => go(context, const BankTransferScreen());

/// UPI collection into the X9 wallet.
void startLoadWallet(BuildContext context) => go(context, const LoadWalletScreen());

/// Active prepaid cards (GET /app/cards).
Future<List<Map<String, dynamic>>> activeCards() async {
  final r = asMap(await Api.instance.get('/app/cards'));
  return asList(r['cards']).map(asMap).where((c) => str(c['status']).toUpperCase() == 'ACTIVE').toList();
}

Future<Map<String, dynamic>?> pickCard(BuildContext context, List<Map<String, dynamic>> cards) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Choose a card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final card in cards)
          ListTile(
            leading: const Icon(Icons.credit_card_rounded, color: X9Colors.primary),
            title: Text(str(card['masked_number'], str(card['card_ref'], 'Card'))),
            subtitle: Text('${str(card['card_type'], 'VIRTUAL')} · ${str(card['program'], 'COMMON')}'
                '${card['provider_balance'] != null ? ' · ${money(asInt(card['provider_balance']))}' : ''}'),
            onTap: () => Navigator.pop(c, card),
          ),
        const SizedBox(height: 12),
      ]),
    ),
  );
}

Future<String?> _askMobile(BuildContext context) {
  final ctrl = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) {
      String? error;
      return StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Send to X9 user', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Mobile number',
                prefixText: '+91  ',
                counterText: '',
                errorText: error,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (!RegExp(r'^[6-9]\d{9}$').hasMatch(v)) {
                  setS(() => error = 'Enter a valid 10-digit mobile number');
                  return;
                }
                Navigator.pop(c, v);
              },
              child: const Text('Continue'),
            ),
          ]),
        ),
      );
    },
  );
}
