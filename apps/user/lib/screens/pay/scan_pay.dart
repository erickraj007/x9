import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/upi_apps.dart';
import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/rate_sheet.dart';
import '../../widgets/result_screen.dart';
import '../history/receipt_screen.dart';
import 'bill_review_screen.dart';

bool _acceptQr(String v) => v.startsWith('x9pay://') || v.toLowerCase().startsWith('upi://');

/// Scan & Pay: X9 bill QR → claim → bill review; UPI QR → offer the phone's UPI app.
Future<void> startScanPay(BuildContext context) async {
  final v = await QrScanPage.open(
    context,
    title: 'Scan & Pay',
    hint: 'Scan the X9 bill QR shown by the merchant',
    accept: _acceptQr,
  );
  if (v == null || !context.mounted) return;
  await handleScannedCode(context, v);
}

Future<void> handleScannedCode(BuildContext context, String v) async {
  if (v.toLowerCase().startsWith('upi://')) {
    await _offerUpiApp(context, v);
    return;
  }
  Map<String, dynamic> r;
  try {
    r = asMap(await withProgress(context, () => Api.instance.post('/app/invoices/claim', {'payload': v}), label: 'Fetching bill…'));
  } catch (e) {
    if (context.mounted) await _showQrError(context, e);
    return;
  }
  if (!context.mounted) return;
  final invoice = asMap(r['invoice']);
  final balance = r['balance'] == null ? AppState.instance.knownClubBalance : asInt(r['balance']);
  go(context, BillReviewScreen(invoice: invoice, walletBalance: balance));
}

/// "Pay with UPI app" quick action: scan any UPI QR and hand it to the phone's UPI app chooser.
Future<void> startUpiAppPay(BuildContext context) async {
  final proceed = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: context.x9.primarySoft, shape: BoxShape.circle),
            child: const Icon(Icons.qr_code_2_rounded, color: X9Colors.primary, size: 38),
          ),
          const SizedBox(height: 14),
          Text('Pay with any UPI app', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Scan the merchant\'s UPI QR. X9 opens your UPI app (GPay, PhonePe, Paytm, BHIM…) with the amount filled in — you approve it there with your UPI PIN.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.x9.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: () => Navigator.pop(c, 'scan'), icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan UPI QR')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'id'), icon: const Icon(Icons.account_balance_rounded), label: const Text('Pay to a UPI ID, choose UPI app')),
          TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
        ]),
      ),
    ),
  );
  if (proceed == null || !context.mounted) return;
  if (proceed == 'id') {
    final link = await _askUpiId(context);
    if (link != null && context.mounted) await payWithUpiApp(context, link);
    return;
  }
  final v = await QrScanPage.open(context, title: 'Scan UPI QR', hint: 'Scan any UPI or X9 bill QR', accept: _acceptQr);
  if (v == null || !context.mounted) return;
  if (v.toLowerCase().startsWith('upi://')) {
    await payWithUpiApp(context, v);
  } else {
    await handleScannedCode(context, v);
  }
}

Future<void> _offerUpiApp(BuildContext context, String upi) async {
  final uri = Uri.tryParse(upi);
  final pn = uri?.queryParameters['pn'] ?? '';
  final am = uri?.queryParameters['am'] ?? '';
  final open = await showModalBottomSheet<bool>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_balance_rounded, size: 40, color: X9Colors.primary),
          const SizedBox(height: 10),
          Text(pn.isEmpty ? 'UPI payment' : 'Pay $pn', style: Theme.of(c).textTheme.titleLarge, textAlign: TextAlign.center),
          if (am.isNotEmpty) Text('₹$am', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('This is a UPI QR. Pay it with your UPI app.', textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.open_in_new_rounded), label: const Text('Pay with UPI app')),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        ]),
      ),
    ),
  );
  if (open == true && context.mounted) await payWithUpiApp(context, upi);
}

Future<void> _showQrError(BuildContext context, Object e) {
  final code = e is ApiException ? e.code : null;
  final title = switch (code) {
    'QR_EXPIRED' => 'Bill QR expired',
    'QR_ALREADY_PAID' => 'Already paid',
    'MERCHANT_INACTIVE' => 'Merchant unavailable',
    'QR_INVALID' => 'Invalid QR code',
    _ => 'Could not open the bill',
  };
  final icon = code == 'QR_ALREADY_PAID' ? Icons.task_alt_rounded : Icons.error_outline_rounded;
  return showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      icon: Icon(icon, color: code == 'QR_ALREADY_PAID' ? X9Colors.success : X9Colors.error, size: 40),
      title: Text(title),
      content: Text(friendlyError(e), textAlign: TextAlign.center),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
    ),
  );
}

/// Result screen for a bill / payment-link payment (transaction with optional receipt).
void openPaymentResult(BuildContext ctx, Map<String, dynamic> r, {required int amount, required String merchant, bool replace = true}) {
  final status = str(r['status'], 'SUCCESS').toUpperCase();
  final receipt = asMap(r['receipt']);
  final receiptId = intOrNull(receipt['id']);
  final txnId = intOrNull(r['id']) ?? intOrNull(r['transaction_id']) ?? intOrNull(receipt['transaction_id']);
  final publicRef = r['transaction_id'] is String ? str(r['transaction_id']) : str(asMap(receipt['payload'])['transaction_id']);
  String? msg;
  if (status == 'FAILED') {
    final reason = str(r['failure_reason'], 'The payment could not be completed. No money was taken.');
    msg = reason.toLowerCase().contains('insufficient') ? '$reason Load your wallet and scan again.' : reason;
  } else if (status == 'PENDING') {
    msg = 'Waiting for confirmation. You will get a notification when it completes.';
  }
  final success = status == 'SUCCESS';
  final cashback = success ? asInt(r['cashback_credited'] ?? receipt['cashback_credited']) : 0;
  if (cashback > 0) msg = 'Cashback ${money(cashback)} credited to your X9 wallet.';
  final page = ResultScreen(
    status: status,
    title: success ? 'Paid to $merchant' : 'Payment to $merchant',
    amount: amount,
    message: msg,
    reference: publicRef,
    details: [if (cashback > 0) MapEntry('X9 cashback', '${money(cashback)} credited')],
    actions: [
      if (receiptId != null)
        ResultAction('View receipt', Icons.receipt_long_rounded, (c) => go(c, ReceiptScreen(receiptId: receiptId, initial: receipt))),
      if (success && txnId != null)
        ResultAction('Rate $merchant', Icons.star_rounded, (c) => showRateSheet(c, transactionId: txnId, merchantName: merchant)),
    ],
    onShown: success && txnId != null ? (c) => showRateSheet(c, transactionId: txnId, merchantName: merchant) : null,
  );
  final route = MaterialPageRoute<void>(builder: (_) => page);
  if (replace) {
    Navigator.of(ctx).pushReplacement(route);
  } else {
    Navigator.of(ctx).push(route);
  }
}


/// Manual entry: payee UPI ID, name and amount → a upi://pay link for the UPI-app picker.
Future<String?> _askUpiId(BuildContext context) {
  final vpa = TextEditingController();
  final name = TextEditingController();
  final amt = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      String? err;
      return StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Pay to a UPI ID', textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(controller: vpa, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'UPI ID (name@bank)')),
              const SizedBox(height: 10),
              TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Payee name (optional)')),
              const SizedBox(height: 10),
              TextField(controller: amt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount in ₹ (optional)')),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: X9Colors.error))),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  final id = vpa.text.trim();
                  if (!RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(id)) {
                    setS(() => err = 'Enter a valid UPI ID, for example name@bank');
                    return;
                  }
                  final q = <String, String>{'pa': id, 'cu': 'INR'};
                  if (name.text.trim().isNotEmpty) q['pn'] = name.text.trim();
                  final a = double.tryParse(amt.text.trim());
                  if (a != null && a > 0) q['am'] = a.toStringAsFixed(2);
                  Navigator.pop(c, Uri(scheme: 'upi', host: 'pay', queryParameters: q).toString());
                },
                child: const Text('Choose UPI app'),
              ),
            ]),
          ),
        ),
      );
    },
  );
}
