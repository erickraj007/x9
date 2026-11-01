import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x9_core/x9_core.dart';

/// v6.19 (iPhone only): iOS has no "choose an app" list for `upi://pay` links and does not tell the app which UPI apps
/// are installed. X9 therefore checks the known UPI apps by their own link schemes (listed in Info.plist >
/// LSApplicationQueriesSchemes by the iOS build) and opens the one the customer picks with that app's own link,
/// e.g. `phonepe://pay?pa=...&am=...`. The payment itself is unchanged: same X9 UPI ID, amount and reference, and it is
/// confirmed by the UPI auto-alert / UTR exactly as on Android.
class IosUpiApp {
  const IosUpiApp(this.name, this.links, this.color, this.letter);

  final String name;

  /// Links tried in order; `{q}` is replaced by the query part of the upi:// link (pa, pn, am, tn, tr, cu, mc...).
  final List<String> links;
  final Color color;
  final String letter;

  List<String> get schemes => links.map((l) => l.split('://').first).toSet().toList();
}

/// Known UPI apps on iPhone. A missing app is simply not shown.
const iosUpiApps = <IosUpiApp>[
  IosUpiApp('Google Pay', ['gpay://upi/pay?{q}', 'tez://upi/pay?{q}'], Color(0xFF1A73E8), 'G'),
  IosUpiApp('PhonePe', ['phonepe://pay?{q}'], Color(0xFF5F259F), 'P'),
  IosUpiApp('Paytm', ['paytmmp://pay?{q}', 'paytm://upi/pay?{q}'], Color(0xFF00B9F1), 'P'),
  IosUpiApp('BHIM', ['bhim://upi/pay?{q}', 'bhim://pay?{q}'], Color(0xFF00897B), 'B'),
  IosUpiApp('CRED', ['credpay://upi/pay?{q}'], Color(0xFF1C1C1C), 'C'),
  IosUpiApp('Amazon Pay', ['amazonpay://upi/pay?{q}'], Color(0xFFFF9900), 'a'),
  IosUpiApp('MobiKwik', ['mobikwik://upi/pay?{q}'], Color(0xFF1C64F2), 'M'),
];

Future<bool> _can(String scheme) async {
  try {
    return await canLaunchUrl(Uri.parse('$scheme://'));
  } catch (_) {
    return false;
  }
}

Future<bool> _open(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// UPI apps installed on this iPhone (in the order of [iosUpiApps]).
Future<List<IosUpiApp>> installedIosUpiApps() async {
  final out = <IosUpiApp>[];
  for (final a in iosUpiApps) {
    for (final s in a.schemes) {
      if (await _can(s)) {
        out.add(a);
        break;
      }
    }
  }
  return out;
}

/// Opens [upi] (a `upi://pay?...` link) in the UPI app the customer picks. Returns true when an app was opened.
/// With no UPI app installed it shows [failMessage] and returns false.
Future<bool> openUpiOnIos(BuildContext context, String upi, {String failMessage = 'No UPI app found on this iPhone.'}) async {
  final q = upi.contains('?') ? upi.substring(upi.indexOf('?') + 1) : '';
  final apps = await installedIosUpiApps();
  final anyUpi = await _can('upi');
  if (!context.mounted) return false;
  if (apps.isEmpty && !anyUpi) {
    _toast(context, failMessage);
    return false;
  }
  final uri = Uri.tryParse(upi);
  final pn = uri?.queryParameters['pn'] ?? '';
  final am = uri?.queryParameters['am'] ?? '';
  // -1 = "Other UPI app" (plain upi:// link: iOS opens the UPI app that registered upi:// most recently).
  final pick = await showModalBottomSheet<int>(
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
              for (var i = 0; i < apps.length; i++)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: apps[i].color,
                    child: Text(apps[i].letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(apps[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(c, i),
                ),
              if (anyUpi)
                ListTile(
                  leading: const CircleAvatar(backgroundColor: X9Colors.primary, child: Icon(Icons.account_balance_rounded, color: Colors.white)),
                  title: const Text('Other UPI app', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('BHIM, bank apps and others'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(c, -1),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
  if (pick == null || !context.mounted) return false;
  if (pick == -1) {
    final ok = await _open(upi);
    if (!ok && context.mounted) _toast(context, failMessage);
    return ok;
  }
  final app = apps[pick];
  for (final l in app.links) {
    if (await _open(l.replaceAll('{q}', q))) return true;
  }
  if (context.mounted) _toast(context, 'Could not open ${app.name}. Try another UPI app.');
  return false;
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
}
