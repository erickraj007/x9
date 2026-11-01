/// Offer, GST and cashback arithmetic shared by the user and merchant apps.
///
/// Pure Dart (no Flutter imports) and **integer paise only**, so the same numbers come out on every phone
/// and match the server (docs/OFFERS-V3.md, test vectors V1-V4). Percentages are rounded half-up
/// (0.5 paise goes up), never with floating-point `round()` on a fraction.
library;

/// Offer mode strings used by the API.
const String kOfferPercent = 'PERCENT';
const String kOfferFlat = 'FLAT';

/// `percent` % of [paise], rounded half-up to a whole paisa.
///
/// [percent] has at most 2 decimals (basis points are used internally, so 2.5 and 0.07 are exact).
/// Examples: percentOf(80000, 5) = 4000, percentOf(250, 1) = 3 (2.5 rounds up), percentOf(249, 1) = 2.
int percentOf(int paise, num percent) {
  if (paise <= 0 || percent <= 0) return 0;
  final bp = (percent * 100).round(); // basis points: 5 % -> 500
  return (paise * bp + 5000) ~/ 10000;
}

/// Offer deducted from one line: PERCENT is [value] % of the gross line (mrp x qty), FLAT is [value] paise per
/// unit (x qty). Never more than the gross and never negative.
int offerForLine({required String mode, required num value, required int mrp, int qty = 1}) {
  if (mrp <= 0 || qty <= 0 || value <= 0) return 0;
  final gross = mrp * qty;
  final off = mode.toUpperCase() == kOfferFlat ? value.round() * qty : percentOf(gross, value);
  if (off < 0) return 0;
  return off > gross ? gross : off;
}

/// GST on a net amount. [inclusive] = the price already contains GST (then total == net).
class GstResult {
  const GstResult(this.tax, this.total);

  /// GST amount in paise.
  final int tax;

  /// Net + GST (exclusive) or the net itself (inclusive).
  final int total;
}

/// GST on [net] paise at [gstPercent] %. Same formulas as the billing screen / server:
/// exclusive: tax = round(net x gst / 100), total = net + tax;
/// inclusive: tax = net - round(net x 100 / (100 + gst)), total = net.
GstResult gstOnNet(int net, num gstPercent, {bool inclusive = false}) {
  if (net <= 0 || gstPercent <= 0) return GstResult(0, net < 0 ? 0 : net);
  if (inclusive) {
    final bp = (gstPercent * 100).round();
    // net x 10000 / (10000 + bp), rounded half-up
    final base = (net * 10000 * 2 + (10000 + bp)) ~/ ((10000 + bp) * 2);
    return GstResult(net - base, net);
  }
  final tax = percentOf(net, gstPercent);
  return GstResult(tax, net + tax);
}

/// One priced line (qty 1 by default): MRP, offer deducted, pay balance, GST.
class LineMath {
  const LineMath({required this.mrpTotal, required this.offer, required this.payBalance, required this.gst, required this.payWithGst});

  /// mrp x qty.
  final int mrpTotal;

  /// Offer deducted (paise).
  final int offer;

  /// mrp x qty - offer (the "pay balance", before GST when GST is added on top).
  final int payBalance;
  final int gst;

  /// What the customer pays for this line including GST.
  final int payWithGst;
}

/// Prices one line. V1: lineMath(mrp: 59000, mode: 'FLAT', value: 1000).payBalance == 58000.
LineMath lineMath({
  required int mrp,
  int qty = 1,
  String? mode,
  num value = 0,
  num gstPercent = 0,
  bool inclusive = false,
}) {
  final gross = (mrp < 0 ? 0 : mrp) * (qty < 1 ? 1 : qty);
  final off = mode == null ? 0 : offerForLine(mode: mode, value: value, mrp: mrp, qty: qty < 1 ? 1 : qty);
  final net = gross - off;
  final g = gstOnNet(net, gstPercent, inclusive: inclusive);
  return LineMath(mrpTotal: gross, offer: off, payBalance: net, gst: g.tax, payWithGst: g.total);
}

/// Bill totals from priced lines (GST is on the net of each line).
class BillTotals {
  const BillTotals({required this.mrpTotal, required this.offerTotal, required this.taxableValue, required this.gstTotal, required this.grandTotal});

  final int mrpTotal;
  final int offerTotal;

  /// mrp total - offer total.
  final int taxableValue;
  final int gstTotal;

  /// What the customer pays.
  final int grandTotal;
}

/// Sums [lines] (build them with [lineMath]). V2: taxable 134000, GST 6700, grand 140700.
BillTotals billTotals(Iterable<LineMath> lines) {
  var mrp = 0, off = 0, net = 0, gst = 0, grand = 0;
  for (final l in lines) {
    mrp += l.mrpTotal;
    off += l.offer;
    net += l.payBalance;
    gst += l.gst;
    grand += l.payWithGst;
  }
  return BillTotals(mrpTotal: mrp, offerTotal: off, taxableValue: net, gstTotal: gst, grandTotal: grand);
}

/// Cashback for a bill whose eligible lines have gross [eligibleMrp] paise.
/// FLAT: min(value, eligibleMrp). PERCENT: percentOf(eligibleMrp, value). Then capped by [maxCashback]
/// (when > 0) and by [budgetRemaining] (when not null). V4: PERCENT 5, max 3000, eligible 80000 -> 3000.
int cashbackAmount({
  required String mode,
  required num value,
  required int eligibleMrp,
  int? maxCashback,
  int? budgetRemaining,
}) {
  if (eligibleMrp <= 0 || value <= 0) return 0;
  var c = mode.toUpperCase() == kOfferFlat ? value.round() : percentOf(eligibleMrp, value);
  if (c > eligibleMrp) c = eligibleMrp;
  if (maxCashback != null && maxCashback > 0 && c > maxCashback) c = maxCashback;
  if (budgetRemaining != null) {
    final left = budgetRemaining < 0 ? 0 : budgetRemaining;
    if (c > left) c = left;
  }
  return c < 0 ? 0 : c;
}
