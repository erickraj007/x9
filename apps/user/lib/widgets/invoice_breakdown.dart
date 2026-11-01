import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../util/helpers.dart';
import 'bits.dart';

/// Invoice / receipt lines and totals in the X9 order: lines (MRP, offer, net) -> MRP / net total -> GST ->
/// TOTAL TO PAY -> the X9 cashback line.
///
/// [data] is an invoice (`POST /app/invoices/claim`) or a receipt payload. New fields (`summary`, item `mrp`,
/// `cashback`) are used when present; older payloads fall back to gross / offer / tax / final amounts.
/// [paid] switches the wording to "TOTAL PAID" and "Cashback ₹100.00 credited"; [cashbackCredited] is the
/// `cashback_credited` value of the pay response / receipt (paise).
class InvoiceBreakdown extends StatelessWidget {
  const InvoiceBreakdown({super.key, required this.data, this.paid = false, this.cashbackCredited = 0});

  final Map<String, dynamic> data;
  final bool paid;
  final int cashbackCredited;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final green = p.statusText(X9Colors.success);
    final items = asList(data['items']).map(asMap).toList();
    final summary = asMap(data['summary']);
    final mrpTotal = asInt(summary['mrp_total'] ?? data['gross_amount']);
    final offerTotal = asInt(summary['offer_total'] ?? data['offer_amount']);
    final taxable = summary['taxable_value'] != null ? asInt(summary['taxable_value']) : mrpTotal - offerTotal;
    final gst = asInt(summary['gst_total'] ?? data['tax_amount']);
    final grand = asInt(summary['grand_total'] ?? data['final_amount']);
    final gstIncluded = gst > 0 && taxable + gst != grand;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final it in items) _line(context, it, green),
      if (items.isNotEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: DashedLine()),
      if (offerTotal > 0) ...[
        KvRow('MRP total', money(mrpTotal)),
        KvRow('Offers', '− ${money(offerTotal)}', valueColor: green),
        KvRow('Net total', money(taxable)),
      ] else if (mrpTotal > 0 && (gst > 0))
        KvRow('Item total', money(mrpTotal)),
      if (gst > 0) KvRow(gstIncluded ? 'GST (included)' : 'GST', money(gst)),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: Text(paid ? 'TOTAL PAID' : 'TOTAL TO PAY', style: TextStyle(color: p.text, fontWeight: FontWeight.w700, letterSpacing: 0.6))),
        Text(money(grand), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.text, fontFeatures: X9Text.tabular)),
      ]),
      ..._cashback(context),
    ]);
  }

  Widget _line(BuildContext context, Map<String, dynamic> it, Color green) {
    final p = context.x9;
    final qty = asInt(it['quantity']) <= 0 ? 1 : asInt(it['quantity']);
    final mrp = asInt(it['mrp'] ?? it['unit_price']);
    final off = asInt(it['offer_amount']);
    final net = mrp > 0 ? mrp * qty - off : asInt(it['line_total'] ?? it['gross_amount']);
    final mode = str(it['offer_mode']).toUpperCase();
    final value = it['offer_value'];
    var tag = '';
    if (off > 0) {
      if (mode == 'PERCENT' && asDouble(value) > 0) {
        final v = asDouble(value);
        tag = '${v == v.roundToDouble() ? v.toInt() : v}% off';
      } else if (mode == 'FLAT' && asInt(value) > 0) {
        tag = '${money(asInt(value), compact: true)} off each';
      }
    }
    final gst = asDouble(it['gst_percent']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(str(it['name'], 'Item'), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '$qty × ${money(mrp)}${gst > 0 ? ' · GST ${gst == gst.roundToDouble() ? gst.toInt() : gst}%' : ''}',
              style: TextStyle(color: p.textSecondary, fontSize: 12),
            ),
            if (off > 0) Text('Offer − ${money(off)}${tag.isEmpty ? '' : ' ($tag)'}', style: TextStyle(color: green, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (off > 0) Text(money(mrp * qty), style: TextStyle(color: p.textSecondary, fontSize: 11.5, decoration: TextDecoration.lineThrough)),
          Text(money(net), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  List<Widget> _cashback(BuildContext context) {
    final p = context.x9;
    final cb = asMap(data['cashback']);
    final status = str(cb['status']).toUpperCase();
    var amount = asInt(cb['amount']);
    final credited = cashbackCredited > 0 || (paid && status == 'CREDITED');
    if (credited && cashbackCredited > 0) amount = cashbackCredited;
    if (amount <= 0) return const [];
    final green = p.statusText(X9Colors.success);
    String line;
    String sub;
    IconData icon = Icons.savings_rounded;
    if (credited) {
      line = 'Cashback ${money(amount)} credited';
      sub = 'Added to your X9 wallet';
    } else if (paid && status == 'SKIPPED') {
      line = 'Cashback ${money(amount)} not given';
      sub = 'The shop could not fund the cashback this time.';
      icon = Icons.info_outline_rounded;
    } else if (paid && status == 'NO_CUSTOMER') {
      line = 'Cashback ${money(amount)} not given';
      sub = 'Pay with your X9 account to get cashback.';
      icon = Icons.info_outline_rounded;
    } else {
      line = 'X9 cashback ${money(amount)} will be credited to your X9 wallet';
      sub = paid ? 'It is added right after the payment is completed.' : 'You get it the moment this bill is paid.';
    }
    final warn = icon == Icons.info_outline_rounded;
    final c = warn ? X9Colors.warning : X9Colors.success;
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), border: Border.all(color: c.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: warn ? p.statusText(X9Colors.warning) : green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line, style: TextStyle(fontWeight: FontWeight.w700, color: p.text, height: 1.25)),
              Text(sub, style: TextStyle(color: p.textSecondary, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    ];
  }
}
