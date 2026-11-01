import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x9_core/x9_core.dart';

import '../screens/kyc/kyc_entry.dart';
import '../services/upi_apps_ios.dart';

/// Small JSON helpers: the API returns plain maps/lists; these keep the screens null-safe.
Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

/// A list from a plain JSON array or from a wrapper such as a Laravel paginator ({data: [...]}).
List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  if (v is Map) {
    for (final k in const ['data', 'results', 'items', 'claims', 'links', 'cards', 'transactions', 'reviews', 'lines', 'notifications']) {
      final x = v[k];
      if (x is List) return x;
      if (x is Map && x['data'] is List) return x['data'] as List;
    }
  }
  return const [];
}

String str(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString();
  return s.isEmpty ? fallback : s;
}

/// "name" of a value that may be a map ({name: ...}) or already a string.
String nameOf(dynamic v, [String fallback = '']) {
  if (v is Map) return str(v['name'], fallback);
  return str(v, fallback);
}

int? intOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.toInt();
}

bool asBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

/// "30% OFF" / "₹100 OFF" / offer text.
String offerLabel(dynamic offer, {double? percent}) {
  final o = asMap(offer);
  final p = asDouble(o['percent'] ?? percent);
  final flat = asInt(o['flat']);
  if (p > 0) return '${_trim(p)}% OFF';
  if (flat > 0) return '${money(flat, compact: true)} OFF';
  final t = str(o['text']);
  return t;
}

String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

String fmtKm(dynamic km) {
  if (km == null) return '';
  final d = asDouble(km);
  if (d < 1) return '${(d * 1000).round()} m';
  return '${d.toStringAsFixed(d < 10 ? 1 : 0)} km';
}

/// "+91 98765 43210" for a stored mobile ("919876543210" / "9876543210").
String fmtMobile(String? m) {
  final s = (m ?? '').replaceAll(RegExp(r'\D'), '');
  final t = s.length > 10 ? s.substring(s.length - 10) : s;
  if (t.length != 10) return m ?? '';
  return '+91 ${t.substring(0, 5)} ${t.substring(5)}';
}

Future<T?> go<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));

/// Opens a link in the matching app (Google Maps, UPI app, dialer).
Future<bool> openExternal(BuildContext context, String? url, {String failMessage = 'No app found to open this.'}) async {
  if (url == null || url.isEmpty) return false;
  // v6.19 iPhone: a upi:// link opens the UPI app the customer picks (Google Pay, PhonePe, Paytm...). Android is unchanged.
  if (Platform.isIOS && url.toLowerCase().startsWith('upi:')) return openUpiOnIos(context, url, failMessage: failMessage);
  bool ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) showError(context, failMessage);
  return ok;
}

/// Readable message for the payment / QR error codes.
String friendlyError(Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'QR_INVALID':
        return 'This QR code is not valid. Ask the merchant to show a fresh bill QR.';
      case 'QR_EXPIRED':
        return 'This bill QR has expired. Ask the merchant to generate a new one.';
      case 'QR_ALREADY_PAID':
        return 'This bill is already paid. No money was taken again.';
      case 'MERCHANT_INACTIVE':
        return 'This merchant cannot receive X9 payments right now.';
      case 'INSUFFICIENT_FUNDS':
      case 'INSUFFICIENT_BALANCE':
        return 'Insufficient balance. Load your X9 wallet and try again.';
      case 'TXN_MPIN_REQUIRED':
        return 'Enter your MPIN to approve this transaction.';
      case 'TXN_CANCELLED':
      case 'TXN_OTP_CANCELLED':
        return 'Transaction cancelled.';
      case 'CARD_TO_WALLET_BLOCKED':
        return 'Money cannot be moved from the prepaid card back to the X9 wallet.';
      case 'TXN_AUTH_REQUIRED':
      case 'TXN_AUTH_INVALID':
        return 'This phone is not approved for payments. Sign out and sign in again to re-register it.';
      case 'KYC_REQUIRED':
        return 'Complete KYC to use wallet, prepaid card and banking.';
      case 'OFFER_CODE_INVALID':
        return 'Offer code is not valid.';
    }
    return e.display;
  }
  return e.toString();
}

void showFriendlyError(BuildContext context, Object e) {
  if (isKycRequired(e)) {
    // 403 KYC_REQUIRED: explain and offer the KYC screen instead of a bare error.
    showKycGate(context);
    return;
  }
  if (e is ApiException && e.code == 'CANCELLED') return; // Cancel pressed on a confirmation
  if (classifyError(e) != null) {
    showErrorDialog(context, e); // low balance / user not valid / server down (+ Contact support)
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(friendlyError(e), style: const TextStyle(color: Colors.white)), backgroundColor: X9Colors.error));
}

/// Blocking progress dialog while [task] runs. Returns the task result (rethrows errors).
Future<T> withProgress<T>(BuildContext context, Future<T> Function() task, {String label = 'Please wait…'}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18)),
          child: Material(
            type: MaterialType.transparency,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6)),
              const SizedBox(width: 16),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    nav.pop();
  }
}
