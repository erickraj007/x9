import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../util/helpers.dart';
import 'bits.dart';
import 'invoice_breakdown.dart';

/// Clean printable receipt card (rendered to PNG for "Save to gallery" / share). Always light themed.
class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.payload, this.number, this.cashbackCredited = 0});

  /// GET /app/receipts/{id} `payload`.
  final Map<String, dynamic> payload;
  final String? number;

  /// `cashback_credited` of the receipt row (paise); the payload's own value is used when this is 0.
  final int cashbackCredited;

  @override
  Widget build(BuildContext context) {
    final p = payload;
    final m = asMap(p['merchant']);
    final loc = asMap(p['location']);
    final offer = asInt(asMap(p['summary'])['offer_total'] ?? p['offer_amount']);
    final total = asInt(asMap(p['summary'])['grand_total'] ?? p['final_amount']);
    // A receipt is a paper document that is saved as an image: it is always drawn with the light
    // palette. The Builder gives the children a context that sits below the light Theme.
    return Theme(
      data: x9LightTheme(),
      child: Builder(builder: (context) {
        final pal = context.x9;
        return Container(
          decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: pal.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(color: pal.surface, border: Border(bottom: BorderSide(color: pal.border))),
              child: Row(children: [
                const X9Logo.mark(height: 40, brightness: Brightness.light),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Eyebrow('Payment receipt', textAlign: TextAlign.end),
                    const SizedBox(height: 2),
                    Text(str(m['shop_name'], 'Merchant'), textAlign: TextAlign.end, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 18)),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: DefaultTextStyle(
                style: TextStyle(color: pal.text, fontSize: 13.5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (str(loc['address']).isNotEmpty)
                    Text('${str(loc['name'])}${str(loc['name']).isNotEmpty ? ', ' : ''}${str(loc['address'])}', style: TextStyle(color: pal.textSecondary, fontSize: 12)),
                  if (str(m['gst_number']).isNotEmpty) Text('GSTIN ${str(m['gst_number'])}', style: TextStyle(color: pal.textSecondary, fontSize: 12)),
                  const SizedBox(height: 10),
                  Center(
                    child: Column(children: [
                      Text('Amount paid', style: TextStyle(color: pal.textSecondary, fontSize: 12)),
                      Text(money(total), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: pal.text, fontFeatures: X9Text.tabular)),
                      const SizedBox(height: 4),
                      const StatusChip('PAID'),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  const DashedLine(),
                  const SizedBox(height: 10),
                  InvoiceBreakdown(data: p, paid: true, cashbackCredited: cashbackCredited > 0 ? cashbackCredited : asInt(p['cashback_credited'])),
                  const SizedBox(height: 6),
                  const DashedLine(),
                  const SizedBox(height: 6),
                  KvRow('Paid by', _mode(str(p['payment_mode']))),
                  if (str(p['invoice_number']).isNotEmpty) KvRow('Invoice no.', str(p['invoice_number'])),
                  if ((number ?? '').isNotEmpty) KvRow('Receipt no.', number!),
                  if (str(p['transaction_id']).isNotEmpty) KvRow('Transaction ID', str(p['transaction_id'])),
                  if (str(p['provider_reference']).isNotEmpty) KvRow('Bank ref.', str(p['provider_reference'])),
                  KvRow('Date', fmtDate(p['paid_at'])),
                  if (offer > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: pal.primarySoft, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(Icons.savings_rounded, color: pal.onPrimarySoft, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('You saved ${money(offer)} with X9', style: TextStyle(fontWeight: FontWeight.w600, color: pal.onPrimarySoft))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Center(child: Text('Thank you for paying with X9', style: TextStyle(color: pal.textSecondary, fontSize: 11.5))),
                ]),
              ),
            ),
          ]),
        );
      }),
    );
  }

  static String _mode(String m) {
    switch (m.toUpperCase()) {
      case 'WALLET':
        return 'X9 Club wallet';
      case 'CARD':
        return 'X9 prepaid card';
      case 'UPI':
        return 'UPI';
      case 'CASH':
        return 'Cash';
    }
    return m.isEmpty ? '—' : m;
  }
}
