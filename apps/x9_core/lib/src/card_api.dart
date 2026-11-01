import 'api.dart';
import 'card_models.dart';

/// User-side v4 card endpoints (docs/PREPAID-CARD-V4.md). Every call returns typed models;
/// errors surface as [ApiException] like the rest of [Api].
class CardApi {
  CardApi._();

  /// `GET /app/cards/charges` - the fee table.
  static Future<List<CardFeeRule>> charges() async => parseCardCharges(await Api.instance.get('/app/cards/charges'));

  /// `GET /app/cards/offers` - LIVE and upcoming card offers for this user.
  static Future<List<CardOffer>> offers() async => parseCardOffers(await Api.instance.get('/app/cards/offers'));

  /// `GET /app/cards/{card}/fee-preview?code=&amount=` (amount in paise; [code] defaults to LOAD).
  static Future<FeePreview> feePreview(int cardId, int amount, {String code = 'LOAD'}) async =>
      FeePreview.fromJson(await Api.instance.get('/app/cards/$cardId/fee-preview', {'code': code, 'amount': amount}));

  /// `POST /app/cards/{card}/load` as a signed money call. The caller must have unlocked the phone first
  /// (AppLock.confirm). Pass the same [idempotencyKey] when retrying one load.
  static Future<CardLoadResult> load(int cardId, int amount, {String? idempotencyKey}) async {
    final r = await Api.instance.money('POST', '/app/cards/$cardId/load', {'amount': amount}, amount: amount, idempotencyKey: idempotencyKey);
    return CardLoadResult.fromJson(r);
  }
}
