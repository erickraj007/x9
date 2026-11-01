/// Models for the v4 prepaid card endpoints (docs/PREPAID-CARD-V4.md sections 4 and 5).
/// Parsing is tolerant: numbers may arrive as int, double or string, and missing fields become null / 0.
library;

import 'card_math.dart';
import 'offer_math.dart';

// ---- tolerant JSON readers (private on purpose: the apps have their own asMap / asInt helpers) ----

int _i(dynamic v) => v is int ? v : (v is num ? v.round() : (int.tryParse('${v ?? ''}') ?? (double.tryParse('${v ?? ''}')?.round() ?? 0)));
int? _iOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.round();
  final s = v.toString();
  if (s.isEmpty) return null;
  return int.tryParse(s) ?? double.tryParse(s)?.round();
}

double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
String _s(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final t = v.toString();
  return t.isEmpty ? fallback : t;
}

bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

/// A list from a plain array or from a wrapper map under one of [keys] (or `data`).
List<dynamic> _l(dynamic v, [List<String> keys = const []]) {
  if (v is List) return v;
  if (v is Map) {
    for (final k in [...keys, 'data']) {
      final x = v[k];
      if (x is List) return x;
      if (x is Map && x['data'] is List) return x['data'] as List;
    }
  }
  return const [];
}

/// "1" for 1.00, "2.5" for 2.50 (percent text without trailing zeros).
String cardPercentText(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var t = v.toStringAsFixed(2);
  while (t.endsWith('0')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// Whole rupees without decimals when possible: 5000 paise -> "₹50", 4550 -> "₹45.50".
String _rupees(int paise) {
  final neg = paise < 0;
  final p = neg ? -paise : paise;
  final whole = p ~/ 100;
  final frac = p % 100;
  final w = _group(whole);
  final body = frac == 0 ? '₹$w' : '₹$w.${frac.toString().padLeft(2, '0')}';
  return neg ? '-$body' : body;
}

String _group(int n) {
  final s = n.toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Short rupee text for headlines and chips ("₹50", "₹1,000", "₹45.50").
String cardRupees(int paise) => _rupees(paise);

/// Human name of a fee code.
String cardFeeCodeLabel(String code) {
  switch (code.toUpperCase()) {
    case kFeeIssueVirtual:
      return 'Virtual card issue';
    case kFeeIssuePhysical:
      return 'Physical card issue';
    case kFeeLoad:
      return 'Loading money';
    case kFeeReplacement:
      return 'Card replacement';
  }
  return code;
}

/// One card charge (fee rule) as returned by `GET /app/cards/charges` and `GET /admin/card-fees`.
class CardFeeRule {
  const CardFeeRule({
    required this.code,
    required this.label,
    required this.mode,
    required this.value,
    this.minFee,
    this.maxFee,
    this.gstPercent = 18,
    this.description = '',
    this.id,
    this.active = true,
  });

  factory CardFeeRule.fromJson(dynamic json) {
    final j = _m(json);
    return CardFeeRule(
      id: _iOrNull(j['id']),
      code: _s(j['code']).toUpperCase(),
      label: _s(j['label']),
      mode: _s(j['mode'], kOfferFlat).toUpperCase(),
      value: _d(j['value']),
      minFee: _iOrNull(j['min_fee']),
      maxFee: _iOrNull(j['max_fee']),
      gstPercent: j['gst_percent'] == null ? 18 : _d(j['gst_percent']),
      description: _s(j['description']),
      active: j['active'] == null ? true : _b(j['active']),
    );
  }

  final int? id;
  final String code;
  final String label;

  /// FLAT | PERCENT.
  final String mode;

  /// Paise for FLAT, decimal percent for PERCENT.
  final double value;
  final int? minFee;
  final int? maxFee;
  final double gstPercent;
  final String description;
  final bool active;

  bool get isFlat => mode == kOfferFlat;

  /// Display name: the server label, else a friendly name of the code.
  String get title => label.isNotEmpty ? label : cardFeeCodeLabel(code);

  /// "₹99" for FLAT, "1% of the amount" for PERCENT.
  String get valueText => isFlat ? _rupees(value.round()) : '${cardPercentText(value)}% of the amount';

  /// "Min ₹5 · Max ₹50" (empty when neither bound exists).
  String get limitsText {
    final parts = <String>[
      if (minFee != null) 'Min ${_rupees(minFee!)}',
      if (maxFee != null) 'Max ${_rupees(maxFee!)}',
    ];
    return parts.join(' · ');
  }

  /// Fee for [base] paise with an optional [waiverPercent] (same arithmetic as the server).
  CardFeeResult feeFor(int base, {num waiverPercent = 0}) =>
      cardFee(mode: mode, value: value, minFee: minFee, maxFee: maxFee, gstPercent: gstPercent, base: code == kFeeLoad ? base : 0, waiverPercent: waiverPercent);
}

/// A card offer (cashback on loads or a fee waiver) from `GET /app/cards/offers` or the admin endpoints.
/// The user app never receives the budget fields (they stay null / 0).
class CardOffer {
  const CardOffer({
    required this.id,
    required this.title,
    required this.type,
    this.description = '',
    this.headline = '',
    this.appliesTo = 'LOAD',
    this.mode = kOfferPercent,
    this.value = 0,
    this.maxCashback,
    this.minAmount,
    this.budgetTotal,
    this.budgetUsed = 0,
    this.perUserLimit,
    this.startsAt,
    this.endsAt,
    this.audience = 'ALL',
    this.paused = false,
    this.suspendedAt,
    this.suspendedReason = '',
    this.status = '',
  });

  factory CardOffer.fromJson(dynamic json) {
    final j = _m(json);
    return CardOffer(
      id: _i(j['id']),
      title: _s(j['title'], 'Card offer'),
      type: _s(j['type']).toUpperCase(),
      description: _s(j['description']),
      headline: _s(j['headline']),
      appliesTo: _s(j['applies_to'], 'LOAD').toUpperCase(),
      mode: _s(j['mode'], kOfferPercent).toUpperCase(),
      value: _d(j['value']),
      maxCashback: _iOrNull(j['max_cashback']),
      minAmount: _iOrNull(j['min_amount']),
      budgetTotal: _iOrNull(j['budget_total']),
      budgetUsed: _i(j['budget_used']),
      perUserLimit: _iOrNull(j['per_user_limit']),
      startsAt: _s(j['starts_at']).isEmpty ? null : _s(j['starts_at']),
      endsAt: _s(j['ends_at']).isEmpty ? null : _s(j['ends_at']),
      audience: _s(j['audience'], 'ALL').toUpperCase(),
      paused: _b(j['paused']),
      suspendedAt: _s(j['suspended_at']).isEmpty ? null : _s(j['suspended_at']),
      suspendedReason: _s(j['suspended_reason']),
      status: _s(j['status']).toUpperCase(),
    );
  }

  final int id;
  final String title;

  /// LOAD_CASHBACK | FEE_WAIVER.
  final String type;
  final String description;

  /// Server sentence such as "2% cashback up to ₹50 on loads of ₹500+".
  final String headline;
  final String appliesTo;
  final String mode;
  final double value;
  final int? maxCashback;
  final int? minAmount;
  final int? budgetTotal;
  final int budgetUsed;
  final int? perUserLimit;

  /// ISO-8601 (UTC) strings.
  final String? startsAt;
  final String? endsAt;
  final String audience;
  final bool paused;
  final String? suspendedAt;
  final String suspendedReason;

  /// DRAFT | SCHEDULED | LIVE | PAUSED | ENDED | BUDGET_EXHAUSTED (| SUSPENDED when suspended).
  final String status;

  bool get isCashback => type == kCardOfferCashback;
  bool get isWaiver => type == kCardOfferWaiver;
  bool get isSuspended => suspendedAt != null || status == 'SUSPENDED';
  bool get isLive => status == 'LIVE';
  DateTime? get endsAtTime => endsAt == null ? null : DateTime.tryParse(endsAt!);

  /// The arithmetic view of this offer (for local previews).
  CardOfferRule toRule() => CardOfferRule(
        type: type,
        appliesTo: appliesTo,
        mode: mode,
        value: value,
        maxCashback: maxCashback,
        minAmount: minAmount,
        id: id,
        title: title,
      );

  /// The server headline, else one built from the rules.
  String get headlineText {
    if (headline.isNotEmpty) return headline;
    final minText = minAmount != null && minAmount! > 0 ? ' on loads of ${_rupees(minAmount!)}+' : '';
    if (isWaiver) {
      final pct = cardPercentText(value);
      return value >= 100 ? 'No card fee$minText' : '$pct% off the card fee$minText';
    }
    final amt = mode == kOfferFlat ? _rupees(value.round()) : '${cardPercentText(value)}%';
    final cap = mode != kOfferFlat && maxCashback != null && maxCashback! > 0 ? ' up to ${_rupees(maxCashback!)}' : '';
    return '$amt cashback$cap$minText';
  }

  /// Short chip text: "2% back", "₹30 back", "No fee", "50% off fee".
  String get chipText {
    if (isWaiver) return value >= 100 ? 'No card fee' : '${cardPercentText(value)}% off fee';
    return mode == kOfferFlat ? '${_rupees(value.round())} back' : '${cardPercentText(value)}% back';
  }
}

/// The cashback a fee preview or load result promises.
class CardCashbackInfo {
  const CardCashbackInfo({this.offerId, this.title = '', required this.amount, this.status = ''});

  factory CardCashbackInfo.fromJson(dynamic json) {
    final j = _m(json);
    return CardCashbackInfo(offerId: _iOrNull(j['offer_id']), title: _s(j['title']), amount: _i(j['amount']), status: _s(j['status']).toUpperCase());
  }

  final int? offerId;
  final String title;
  final int amount;

  /// CREDITED | SKIPPED | PENDING (load result only).
  final String status;
}

/// `GET /app/cards/{card}/fee-preview` response.
class FeePreview {
  const FeePreview({
    required this.amount,
    required this.fee,
    required this.gst,
    required this.totalFee,
    required this.waiverPercent,
    required this.youPay,
    required this.cardCredit,
    this.cashback,
  });

  factory FeePreview.fromJson(dynamic json) {
    final j = _m(json);
    final amount = _i(j['amount']);
    final fee = _i(j['fee']);
    final gst = _i(j['gst']);
    final total = j['total_fee'] == null ? fee + gst : _i(j['total_fee']);
    final cb = j['cashback'];
    return FeePreview(
      amount: amount,
      fee: fee,
      gst: gst,
      totalFee: total,
      waiverPercent: _d(j['waiver_percent']),
      youPay: j['you_pay'] == null ? amount + total : _i(j['you_pay']),
      cardCredit: j['card_credit'] == null ? amount : _i(j['card_credit']),
      cashback: cb is Map ? CardCashbackInfo.fromJson(cb) : null,
    );
  }

  /// A preview made on the phone from [CardLoadQuote] (used while the server answer is on its way).
  factory FeePreview.fromQuote(CardLoadQuote q) => FeePreview(
        amount: q.amount,
        fee: q.fee,
        gst: q.gst,
        totalFee: q.totalFee,
        waiverPercent: q.waiverPercent.toDouble(),
        youPay: q.youPay,
        cardCredit: q.cardCredit,
        cashback: q.cashback > 0 ? CardCashbackInfo(amount: q.cashback) : null,
      );

  final int amount;
  final int fee;
  final int gst;
  final int totalFee;
  final double waiverPercent;
  final int youPay;
  final int cardCredit;
  final CardCashbackInfo? cashback;

  int get cashbackAmount => cashback?.amount ?? 0;
}

/// One line of a card invoice.
class CardInvoiceLine {
  const CardInvoiceLine(this.label, this.amount);
  final String label;

  /// Paise; negative for deductions.
  final int amount;
}

/// `invoice` of the load response: lines, what the person paid and what the card got.
class CardInvoice {
  const CardInvoice({required this.lines, required this.youPaid, required this.cardCredit});

  factory CardInvoice.fromJson(dynamic json) {
    final j = _m(json);
    return CardInvoice(
      lines: [
        for (final r in _l(j['lines']))
          CardInvoiceLine(_s(_m(r)['label']), _i(_m(r)['amount'])),
      ],
      youPaid: _i(j['you_paid']),
      cardCredit: _i(j['card_credit']),
    );
  }

  final List<CardInvoiceLine> lines;
  final int youPaid;
  final int cardCredit;
}

/// `POST /app/cards/{card}/load` response. All the pre-v4 fields stay in [raw]; v4 adds fee, gst, total_fee,
/// cashback and invoice (null / 0 when the server did not send them).
class CardLoadResult {
  const CardLoadResult({
    required this.raw,
    required this.fee,
    required this.gst,
    required this.totalFee,
    this.cashback,
    this.invoice,
  });

  factory CardLoadResult.fromJson(dynamic json) {
    final j = _m(json);
    final cb = j['cashback'];
    final inv = j['invoice'];
    return CardLoadResult(
      raw: j,
      fee: _i(j['fee']),
      gst: _i(j['gst']),
      totalFee: j['total_fee'] == null ? _i(j['fee']) + _i(j['gst']) : _i(j['total_fee']),
      cashback: cb is Map ? CardCashbackInfo.fromJson(cb) : null,
      invoice: inv is Map ? CardInvoice.fromJson(inv) : null,
    );
  }

  final Map<String, dynamic> raw;
  final int fee;
  final int gst;
  final int totalFee;
  final CardCashbackInfo? cashback;
  final CardInvoice? invoice;

  String get status => _s(raw['status'], 'SUCCESS').toUpperCase();
  String get reference => _s(raw['reference'], _s(raw['transaction_id'], _s(raw['txn_id'])));
  int get amount => _i(raw['amount']);

  /// Cashback that actually reached the wallet (status CREDITED, or no status given).
  int get cashbackCredited {
    final c = cashback;
    if (c == null) return 0;
    if (c.status.isNotEmpty && c.status != 'CREDITED') return 0;
    return c.amount;
  }
}

/// Parses `GET /app/cards/charges` (`{rules:[...]}` or a bare array).
List<CardFeeRule> parseCardCharges(dynamic json) => [for (final r in _l(json, const ['rules'])) CardFeeRule.fromJson(r)];

/// Parses `GET /app/cards/offers` (`{offers:[...]}`, `{data:[...]}` or a bare array).
List<CardOffer> parseCardOffers(dynamic json) => [for (final r in _l(json, const ['offers'])) CardOffer.fromJson(r)];
