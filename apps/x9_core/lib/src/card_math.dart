/// Prepaid card fee, GST, fee-waiver and cashback arithmetic (docs/PREPAID-CARD-V4.md sections 4, 5 and 7).
///
/// Pure Dart (no Flutter imports) and **integer paise only**. Percentages are rounded half-up through
/// [percentOf] from offer_math.dart, so the numbers match the server on every phone.
library;

import 'offer_math.dart';

/// Fee rule codes.
const String kFeeIssueVirtual = 'ISSUE_VIRTUAL';
const String kFeeIssuePhysical = 'ISSUE_PHYSICAL';
const String kFeeLoad = 'LOAD';
const String kFeeReplacement = 'REPLACEMENT';

/// Card offer types.
const String kCardOfferCashback = 'LOAD_CASHBACK';
const String kCardOfferWaiver = 'FEE_WAIVER';

/// Raw fee before min / max: FLAT is [value] paise, PERCENT is [value] % of [base] (half-up).
int cardFeeRaw({required String mode, required num value, int base = 0}) {
  if (value <= 0) return 0;
  if (mode.toUpperCase() == kOfferFlat) return value.round();
  return percentOf(base, value);
}

/// Clamps [raw] into [minFee] .. [maxFee] (either may be null = no bound).
int clampFee(int raw, {int? minFee, int? maxFee}) {
  var f = raw;
  if (minFee != null && f < minFee) f = minFee;
  if (maxFee != null && f > maxFee) f = maxFee;
  return f < 0 ? 0 : f;
}

/// Fee after a waiver of [waiverPercent] % (0..100): `fee - round(fee * waiver / 100)`.
int applyWaiver(int fee, num waiverPercent) {
  if (fee <= 0 || waiverPercent <= 0) return fee < 0 ? 0 : fee;
  final w = waiverPercent > 100 ? 100 : waiverPercent;
  final left = fee - percentOf(fee, w);
  return left < 0 ? 0 : left;
}

/// GST on a fee: `round(fee * gstPercent / 100)`.
int gstOnFee(int fee, num gstPercent) => percentOf(fee, gstPercent);

/// Result of [cardFee].
class CardFeeResult {
  const CardFeeResult({required this.raw, required this.fee, required this.gst, required this.totalFee, required this.waiverPercent});

  /// Fee after min / max, before the waiver.
  final int raw;

  /// Fee after the waiver (what is taxed).
  final int fee;
  final int gst;

  /// fee + gst.
  final int totalFee;
  final num waiverPercent;
}

/// One fee rule applied to [base] (the load amount for LOAD, 0 for issue / replacement).
/// No rule (use [cardFee] with value 0 or skip the call) means fee 0.
/// F1: PERCENT 1.00, min 500, max 5000, gst 18, base 100000 -> fee 1000, gst 180, total 1180.
CardFeeResult cardFee({
  required String mode,
  required num value,
  int? minFee,
  int? maxFee,
  num gstPercent = 18,
  int base = 0,
  num waiverPercent = 0,
}) {
  final raw = clampFee(cardFeeRaw(mode: mode, value: value, base: base), minFee: minFee, maxFee: maxFee);
  final fee = applyWaiver(raw, waiverPercent);
  final gst = gstOnFee(fee, gstPercent);
  return CardFeeResult(raw: raw, fee: fee, gst: gst, totalFee: fee + gst, waiverPercent: waiverPercent);
}

/// A card offer reduced to what the arithmetic needs.
class CardOfferRule {
  const CardOfferRule({
    required this.type,
    this.appliesTo = 'ANY',
    this.mode = kOfferPercent,
    this.value = 0,
    this.maxCashback,
    this.minAmount,
    this.id,
    this.title = '',
  });

  /// LOAD_CASHBACK | FEE_WAIVER.
  final String type;

  /// LOAD | ISSUE_VIRTUAL | ISSUE_PHYSICAL | ANY (FEE_WAIVER only; cashback is always LOAD).
  final String appliesTo;

  /// PERCENT | FLAT (ignored for FEE_WAIVER: value is a percent 1..100).
  final String mode;
  final num value;
  final int? maxCashback;

  /// Minimum load amount in paise (null = none).
  final int? minAmount;
  final int? id;
  final String title;
}

/// Cashback of one LOAD_CASHBACK offer for a load of [amount] paise, or 0 when not eligible
/// (below [CardOfferRule.minAmount]). PERCENT is half-up, capped by max_cashback; FLAT is the value.
/// C1: PERCENT 2.00, max 5000, min 50000: 100000 -> 2000, 1000000 -> 5000, 40000 -> 0.
int cardCashbackFor(CardOfferRule o, int amount) {
  if (o.type.toUpperCase() != kCardOfferCashback) return 0;
  if (amount <= 0 || o.value <= 0) return 0;
  final min = o.minAmount;
  if (min != null && amount < min) return 0;
  var c = o.mode.toUpperCase() == kOfferFlat ? o.value.round() : percentOf(amount, o.value);
  final cap = o.maxCashback;
  if (cap != null && cap > 0 && c > cap) c = cap;
  return c < 0 ? 0 : c;
}

/// The cashback offer that pays most for [amount] (only the largest applies), or null.
CardOfferRule? bestCashbackOffer(Iterable<CardOfferRule> offers, int amount) {
  CardOfferRule? best;
  var bestAmt = 0;
  for (final o in offers) {
    final a = cardCashbackFor(o, amount);
    if (a > bestAmt) {
      bestAmt = a;
      best = o;
    }
  }
  return best;
}

/// Waiver percent (0..100) of the best FEE_WAIVER offer for fee [code] and [base] (the load amount for LOAD, else 0).
/// An offer applies when `appliesTo` is [code] or ANY and `base >= minAmount`. W1: 100 %, min 50000: load 100000 -> 100, 20000 -> 0.
num bestWaiverPercent(Iterable<CardOfferRule> offers, {required String code, int base = 0}) {
  num best = 0;
  for (final o in offers) {
    if (o.type.toUpperCase() != kCardOfferWaiver) continue;
    final at = o.appliesTo.toUpperCase();
    if (at != 'ANY' && at != code.toUpperCase()) continue;
    final min = o.minAmount;
    if (min != null && base < min) continue;
    final p = o.value > 100 ? 100 : o.value;
    if (p > best) best = p;
  }
  return best;
}

/// Everything the Load sheet shows.
class CardLoadQuote {
  const CardLoadQuote({
    required this.amount,
    required this.fee,
    required this.gst,
    required this.totalFee,
    required this.waiverPercent,
    required this.cashback,
    required this.youPay,
    required this.cardCredit,
  });

  /// Load amount.
  final int amount;
  final int fee;
  final int gst;
  final int totalFee;
  final num waiverPercent;

  /// Cashback credited to the X9 wallet after the load (never part of [youPay]).
  final int cashback;

  /// amount + totalFee.
  final int youPay;

  /// What lands on the card (the full amount).
  final int cardCredit;
}

/// Full local quote for loading [amount] paise: the LOAD [rule] (null = no fee), plus any [offers]
/// (best waiver on the fee, best cashback on the amount; one of each may combine).
/// F1 -> you_pay 101180, card_credit 100000. W1 (100 % waiver) -> fee 0, you_pay 100000.
CardLoadQuote cardLoadQuote({
  required int amount,
  String? mode,
  num value = 0,
  int? minFee,
  int? maxFee,
  num gstPercent = 18,
  Iterable<CardOfferRule> offers = const [],
}) {
  final list = offers.toList();
  final waiver = bestWaiverPercent(list, code: kFeeLoad, base: amount);
  final f = mode == null
      ? const CardFeeResult(raw: 0, fee: 0, gst: 0, totalFee: 0, waiverPercent: 0)
      : cardFee(mode: mode, value: value, minFee: minFee, maxFee: maxFee, gstPercent: gstPercent, base: amount, waiverPercent: waiver);
  final best = bestCashbackOffer(list, amount);
  final cb = best == null ? 0 : cardCashbackFor(best, amount);
  return CardLoadQuote(
    amount: amount,
    fee: f.fee,
    gst: f.gst,
    totalFee: f.totalFee,
    waiverPercent: waiver,
    cashback: cb,
    youPay: amount + f.totalFee,
    cardCredit: amount,
  );
}
