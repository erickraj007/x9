import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';

/// Result of a card load: tick, amount, the invoice (load, card fee, GST, cashback, you paid) and the
/// cashback that was credited to the X9 wallet.
class CardLoadSuccessScreen extends StatelessWidget {
  const CardLoadSuccessScreen({super.key, required this.result, required this.card});

  final CardLoadResult result;
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final pal = context.x9;
    final status = result.status;
    final failed = status == 'FAILED';
    final done = status == 'SUCCESS' || status == 'COMPLETED' || status == 'LOADED';
    final color = failed ? X9Colors.error : (done ? X9Colors.success : X9Colors.primary);
    final icon = failed ? Icons.close_rounded : (done ? Icons.check_rounded : Icons.schedule_rounded);
    final title = failed ? 'Load failed' : (done ? 'Card loaded' : 'Load in progress');
    final invoice = result.invoice;
    final cardCredit = invoice != null && invoice.cardCredit > 0 ? invoice.cardCredit : result.amount;
    final cashback = result.cashbackCredited;
    final ref = result.reference;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withValues(alpha: 0.16), Theme.of(context).scaffoldBackgroundColor], begin: Alignment.topCenter, end: Alignment.center),
        ),
        child: SafeArea(
          child: Column(children: [
            Align(alignment: Alignment.topRight, child: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop())),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 26, spreadRadius: 3)]),
                      child: Icon(icon, color: Colors.white, size: 56),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  if (cardCredit > 0) ...[
                    const SizedBox(height: 6),
                    Text(money(cardCredit), textAlign: TextAlign.center, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -1)),
                    Text('added to ${str(card['masked_number'], 'your X9 prepaid card')}', textAlign: TextAlign.center, style: TextStyle(color: pal.textSecondary, fontSize: 12.5)),
                  ],
                  if (!done && !failed) ...[
                    const SizedBox(height: 10),
                    Text('Your card is being loaded. The balance updates as soon as the card network confirms.', textAlign: TextAlign.center, style: TextStyle(color: pal.textSecondary, height: 1.4)),
                  ],
                  const SizedBox(height: 20),
                  if (invoice != null && invoice.lines.isNotEmpty)
                    FeeBreakdown.forInvoice(invoice)
                  else if (result.totalFee > 0 || result.fee > 0)
                    FeeBreakdown(
                      lines: [
                        CardFeeLine('Load', result.amount),
                        CardFeeLine('Card fee', result.fee),
                        CardFeeLine('GST', result.gst, muted: true),
                      ],
                      total: result.amount + result.totalFee,
                      totalLabel: 'You paid',
                    ),
                  if (cashback > 0) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: X9Colors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        const Icon(Icons.savings_rounded, color: X9Colors.success),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${money(cashback)} cashback credited to your X9 wallet',
                            style: TextStyle(fontWeight: FontWeight.w700, color: pal.statusText(X9Colors.success)),
                          ),
                        ),
                      ]),
                    ),
                  ],
                  if (ref.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: ref));
                        showOk(context, 'Reference copied');
                      },
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _RefLine('Reference', ref)),
                    ),
                  ],
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Plain label / value line (kept local so this screen needs no other widget file).
class _RefLine extends StatelessWidget {
  const _RefLine(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label, style: TextStyle(color: context.x9.textSecondary)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]);
}
