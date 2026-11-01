import 'package:flutter/material.dart';

import '../bootstrap.dart';
import 'otp_boxes.dart';
import 'pin_pattern.dart';

/// Asks for the WhatsApp code that approves a transaction. Returns the code, or null when cancelled.
/// Registered as [Api.txnOtpPrompt] by [X9Bootstrap]; the code was already sent by Api (POST /auth/txn-otp).
Future<String?> showTxnOtpDialog(String sentTo, int length) async {
  final ctx = X9Bootstrap.navigatorKey?.currentContext;
  if (ctx == null) return null;
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: ctx,
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
      title: const Text('Confirm on WhatsApp'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Enter the $length-digit code we sent to WhatsApp ${sentTo.isEmpty ? 'on your number' : sentTo} to approve this payment.'),
        const SizedBox(height: 16),
        X9OtpBoxes(length: length, controller: c, autofocus: true, onCompleted: (v) => Navigator.of(dctx).pop(v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Cancel'))],
    ),
  );
  c.dispose();
  return (r == null || r.isEmpty) ? null : r;
}

/// Asks for the 4-digit X9 MPIN that approves a transaction. Returns the MPIN, or null when cancelled.
Future<String?> showMpinSheet() async {
  final ctx = X9Bootstrap.navigatorKey?.currentContext;
  if (ctx == null) return null;
  return showModalBottomSheet<String>(
    context: ctx,
    isScrollControlled: true,
    isDismissible: true,
    builder: (sctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Enter your MPIN', style: Theme.of(sctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('MPIN and a WhatsApp code approve every payment.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          PinPad(length: 4, onCompleted: (pin) => Navigator.of(sctx).pop(pin)),
          TextButton(onPressed: () => Navigator.of(sctx).pop(), child: const Text('Cancel')),
        ]),
      ),
    ),
  );
}
