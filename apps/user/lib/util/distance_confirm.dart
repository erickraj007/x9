import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import 'helpers.dart';
import 'travel.dart';

/// v6.13: before an order or an appointment is sent, remind the person how far the shop is and ask for a confirmation.
/// Returns true to go ahead. When the distance is unknown (no location) the dialog is skipped.
Future<bool> confirmDistance(BuildContext context, {required String shopName, required dynamic distanceKm, required String what}) async {
  final km = distanceKm == null ? 0.0 : asDouble(distanceKm);
  if (km <= 0) return true;
  final mins = travelMinutes(km);
  final kmText = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.directions_car_rounded, color: X9Colors.primary, size: 36),
      title: Text('$shopName is $kmText km away', textAlign: TextAlign.center),
      content: Text(
        'It takes about ${fmtMinutes(mins)} to get there. Do you want to send this $what?',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(d, true), style: FilledButton.styleFrom(minimumSize: const Size(120, 44)), child: const Text('Yes, send')),
      ],
    ),
  );
  if (ok == true) Api.instance.markConfirmed();
  return ok == true;
}
