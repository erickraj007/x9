import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';

final RegExp _uuidRe = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// "5" / "2.5" for a percentage.
String trimPct(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

DateTime? parseTime(dynamic iso) {
  final s = str(iso);
  return s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
}

/// "5% OFF" / "₹10 OFF" for a product line of a PRODUCT offer (FLAT value is paise per unit).
String lineOfferLabel(dynamic mode, dynamic value) {
  final m = str(mode).toUpperCase();
  if (m == 'FLAT') {
    final v = asInt(value);
    return v > 0 ? '${money(v, compact: true)} OFF' : '';
  }
  final v = asDouble(value);
  return v > 0 ? '${trimPct(v)}% OFF' : '';
}

/// "₹100 cashback" / "5% cashback" for a cashback object ({mode, value, ...}).
String cashbackShort(dynamic cashback) {
  final c = asMap(cashback);
  if (c.isEmpty) return '';
  if (str(c['mode']).toUpperCase() == 'FLAT') {
    final v = asInt(c['value']);
    return v > 0 ? '${money(v, compact: true)} cashback' : '';
  }
  final v = asDouble(c['value']);
  return v > 0 ? '${trimPct(v)}% cashback' : '';
}

/// Lines that explain a cashback offer's rules (min bill, cap, limit, budget).
List<MapEntry<String, String>> cashbackRules(dynamic cashback) {
  final c = asMap(cashback);
  final out = <MapEntry<String, String>>[];
  final min = asInt(c['min_bill_amount']);
  final max = asInt(c['max_cashback']);
  final limit = asInt(c['per_user_limit']);
  final total = asInt(c['budget_total']);
  final used = asInt(c['budget_used']);
  if (min > 0) out.add(MapEntry('Minimum bill', money(min, compact: true)));
  if (max > 0) out.add(MapEntry('Maximum cashback', money(max, compact: true)));
  if (limit > 0) out.add(MapEntry('Per customer', '$limit time${limit == 1 ? '' : 's'}'));
  if (total > 0) {
    final left = total - used;
    out.add(MapEntry('Offer budget left', left > 0 ? money(left, compact: true) : 'Used up'));
  }
  return out;
}

/// Fire-and-forget analytics for an offer: VIEW | CLICK | SHARE. Errors are ignored.
Future<void> sendPromoEvent(String ref, String event) async {
  if (ref.isEmpty) return;
  try {
    await Api.instance.post('/app/promotions/${Uri.encodeComponent(ref)}/event', {'event': event});
  } catch (_) {}
}

/// Share sheet with the offer's link; counts a SHARE.
Future<void> shareOffer(BuildContext context, {required String ref, required String title, required String shop, required String url}) async {
  if (url.isEmpty) {
    showError(context, 'This offer has no share link yet.');
    return;
  }
  sendPromoEvent(ref, 'SHARE');
  try {
    await Share.share('$title${shop.isEmpty ? '' : ' at $shop'}\n$url', subject: title);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showOk(context, 'Link copied');
  }
}

/// Loads the offer detail for a uuid or a share code.
///
/// 1. `GET /app/promotions/{ref}` (works for the uuid; the server may also accept the code).
/// 2. When [ref] is a code and step 1 says 404 / 400 / 422: `GET /public/promotions/{code}`; if that response carries
///    a uuid, fetch the full detail by uuid, otherwise show the public data (read-only, `public: true`).
Future<Map<String, dynamic>> loadOfferDetail(String ref) async {
  final isUuid = _uuidRe.hasMatch(ref);
  final enc = Uri.encodeComponent(ref);
  try {
    return asMap(await Api.instance.get('/app/promotions/$enc'));
  } on ApiException catch (e) {
    final notFound = e.status == 404 || e.status == 400 || e.status == 422;
    if (isUuid || !notFound) rethrow;
  }
  final pub = asMap(await Api.instance.get('/public/promotions/$enc'));
  final inner = asMap(pub['promotion']);
  final uuid = str(pub['uuid'], str(inner['uuid']));
  if (uuid.isNotEmpty) {
    try {
      return asMap(await Api.instance.get('/app/promotions/${Uri.encodeComponent(uuid)}'));
    } on ApiException {
      // fall through to the public view
    }
  }
  return _fromPublic(pub, ref);
}

/// Public share data -> the same shape as the app detail response.
Map<String, dynamic> _fromPublic(Map<String, dynamic> pub, String code) {
  final m = asMap(pub['merchant']);
  final cb = asMap(pub['cashback']);
  final deep = str(pub['deep_link'], 'x9://offer/$code');
  return {
    'public': true,
    'promotion': {
      'type': cb.isNotEmpty ? 'CASHBACK' : 'PRODUCT',
      'title': pub['title'],
      'description': pub['description'],
      'status': pub['status'],
      'starts_at': pub['starts_at'],
      'ends_at': pub['ends_at'],
      'images': pub['images'],
      'link': {'code': code, 'url': str(pub['url'], str(pub['app_url'])), 'deep_link': deep},
      'cashback_summary': cb['summary'],
    },
    'merchant': {
      'shop_name': m['shop_name'],
      'logo_url': m['logo_url'],
      'locations': [
        {'address': m['address'], 'city': m['city']}
      ],
    },
    'products': [
      for (final raw in asList(pub['products']))
        {
          'name': asMap(raw)['name'],
          'image_url': asMap(raw)['image_url'],
          'mrp': asMap(raw)['mrp'],
          'pay_balance': asMap(raw)['final_price'],
        }
    ],
    'other_products': const [],
    'offers_now': const [],
  };
}
