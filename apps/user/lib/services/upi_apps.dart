import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../util/helpers.dart';

/// v6.13: the UPI apps installed on this phone (Android) and a picker to open one with a upi:// payment link.
class UpiApps {
  static const _ch = MethodChannel('x9/upi');

  static Future<List<Map<String, dynamic>>> installed(String uri) async {
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('apps', {'uri': uri});
      return (r ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> launch(String package, String uri) async {
    try {
      return (await _ch.invokeMethod<bool>('launch', {'package': package, 'uri': uri})) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Shows the phone's UPI apps (GPay, PhonePe, Paytm, BHIM...) to choose from, then opens the chosen one.
/// With no list (iOS, or no app found) it falls back to the system chooser / a clear message.
Future<void> payWithUpiApp(BuildContext context, String upi) async {
  final apps = await UpiApps.installed(upi);
  if (!context.mounted) return;
  if (apps.isEmpty) {
    await openExternal(context, upi, failMessage: 'No UPI app found on this phone. Install GPay, PhonePe, Paytm or BHIM and try again.');
    return;
  }
  final uri = Uri.tryParse(upi);
  final pn = uri?.queryParameters['pn'] ?? '';
  final am = uri?.queryParameters['am'] ?? '';
  final pick = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(pn.isEmpty ? 'Pay with a UPI app' : 'Pay $pn', textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleLarge),
          if (am.isNotEmpty) Text('₹$am', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Choose the UPI app to pay with', textAlign: TextAlign.center, style: TextStyle(color: c.x9.textSecondary)),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final a in apps)
                ListTile(
                  leading: a['icon'] is Uint8List
                      ? Image.memory(a['icon'] as Uint8List, width: 40, height: 40)
                      : const Icon(Icons.account_balance_rounded, color: X9Colors.primary),
                  title: Text(str(a['name'], 'UPI app'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(c, a),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  final ok = await UpiApps.launch(str(pick['package']), upi);
  if (!ok && context.mounted) showError(context, 'Could not open ${str(pick['name'], 'the UPI app')}.');
}
