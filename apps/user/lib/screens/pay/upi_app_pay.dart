import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';

/// Pays [amount] by handing the bill's `upi://pay` link (central X9 UPI ID, exact amount, bill number as reference) to the
/// phone's own UPI app (PhonePe, Google Pay, Paytm, BHIM...). The payment is confirmed automatically by the UPI auto-alert;
/// [isPaid] is polled every 3 s (up to 10 min) while the waiting sheet is open. Returns true once paid.
Future<bool> payWithUpiApp(BuildContext context, {required String intent, required int amount, required Future<bool> Function() isPaid, String? utrPath}) async {
  if (intent.isEmpty) {
    showError(context, 'UPI payment is not available for this bill right now.');
    return false;
  }
  final opened = await openExternal(context, intent, failMessage: 'No UPI app found on this phone. Pay with your X9 wallet or prepaid card instead.');
  if (!opened || !context.mounted) return false;
  final paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WaitForUpi(amount: amount, isPaid: isPaid, utrPath: utrPath),
  );
  return paid == true;
}

class _WaitForUpi extends StatefulWidget {
  const _WaitForUpi({required this.amount, required this.isPaid, this.utrPath});
  final int amount;
  final Future<bool> Function() isPaid;

  /// v6.18.4: POST path for "Paid but not confirmed? Enter UTR" (e.g. /app/invoices/12/utr); null = no UTR button.
  final String? utrPath;

  @override
  State<_WaitForUpi> createState() => _WaitForUpiState();
}

class _WaitForUpiState extends State<_WaitForUpi> {
  Timer? _t;
  int _ticks = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      if (await widget.isPaid()) {
        _t?.cancel();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } catch (_) {
      // offline / busy: next tick
    } finally {
      _busy = false;
    }
    if (++_ticks >= 200 && mounted) Navigator.of(context).pop(false);
  }

  bool _utrSent = false;

  /// v6.18.4: the UPI app shows the UTR / UPI reference; X9 pays the bill (merchant wallet) as soon as the bank alert or
  /// Super Admin confirms that UTR.
  Future<void> _enterUtr() async {
    final c = TextEditingController();
    final utr = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Enter UTR'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, maxLength: 22, decoration: const InputDecoration(labelText: 'UTR / UPI reference', hintText: 'e.g. 931752280301')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, c.text.replaceAll(RegExp(r'\s'), '')), child: const Text('Send')),
        ],
      ),
    );
    if (utr == null || utr.isEmpty || !mounted) return;
    try {
      final r = asMap(await Api.instance.post(widget.utrPath!, {'utr': utr}));
      if (!mounted) return;
      setState(() => _utrSent = true);
      showOk(context, str(r['message'], 'UTR received'));
      if (str(r['status']).toUpperCase() == 'PAID') Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pay ${money(widget.amount)} in your UPI app'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: X9Colors.primary)),
        const SizedBox(height: 16),
        const Text('Finish the payment in your UPI app, then come back here. It is confirmed automatically, usually within a few seconds.', textAlign: TextAlign.center),
      ]),
      actions: [
        if (widget.utrPath != null && !_utrSent) TextButton(onPressed: _enterUtr, child: const Text('Enter UTR')),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
      ],
    );
  }
}
