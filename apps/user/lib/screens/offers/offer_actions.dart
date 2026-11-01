import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import 'offer_code_screen.dart';

/// POST /app/offers/claim → `{code, expires_at, merchant, offer}`.
Future<Map<String, dynamic>> fetchOfferClaim({required String merchantUuid, int? productId, int? adId}) async {
  return asMap(await Api.instance.post('/app/offers/claim', {
    'merchant_uuid': merchantUuid,
    if (productId != null && productId > 0) 'product_id': productId,
    if (adId != null && adId > 0) 'ad_id': adId,
  }));
}

/// "Get offer": claims a code and opens the offer code screen (does not wait for it to close).
Future<void> claimOffer(BuildContext context, {required String merchantUuid, int? productId, int? adId}) async {
  final r = await fetchOfferClaim(merchantUuid: merchantUuid, productId: productId, adId: adId);
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OfferCodeScreen(claim: r)));
}
