import 'package:flutter/material.dart';

import '../card_models.dart';
import 'offers_ui.dart';
import 'theme.dart';
import 'widgets.dart';

/// Paise as "₹20.00", or "−₹20.00" for a negative amount (deductions and cashback).
String cardSignedMoney(int paise) => paise < 0 ? '−${money(-paise)}' : money(paise);

/// One row of a [FeeBreakdown].
class CardFeeLine {
  const CardFeeLine(this.label, this.amount, {this.note, this.muted = false});

  final String label;

  /// Paise; negative values are drawn as "−₹x" in the success colour (cashback, discounts).
  final int amount;

  /// Small grey text under the label, e.g. "credited after load".
  final String? note;

  /// Draw the row in the secondary colour (taxes).
  final bool muted;
}

/// Fee breakdown card: lines, a divider and a bold total. Reused by the Load sheet (live preview) and the
/// success screen (invoice). Money values use tabular figures so the column stays aligned.
class FeeBreakdown extends StatelessWidget {
  const FeeBreakdown({super.key, required this.lines, required this.total, this.totalLabel = 'You pay', this.footnote, this.loading = false});

  /// "Load / Card fee / GST / Cashback" lines of a fee preview. [loading] dims the numbers while a newer
  /// server answer is on its way.
  factory FeeBreakdown.forPreview(FeePreview p, {bool loading = false}) {
    final waived = p.waiverPercent > 0 && p.fee == 0;
    return FeeBreakdown(
      loading: loading,
      lines: [
        CardFeeLine('Load', p.amount),
        CardFeeLine(
          'Card fee',
          p.fee,
          note: p.waiverPercent > 0 ? (waived ? 'Waived by offer' : '${cardPercentText(p.waiverPercent)}% off by offer') : null,
        ),
        CardFeeLine('GST', p.gst, muted: true),
        if (p.cashbackAmount > 0) CardFeeLine('Cashback', -p.cashbackAmount, note: 'credited after load'),
      ],
      total: p.youPay,
      footnote: p.cardCredit > 0 ? '${money(p.cardCredit)} goes onto your card' : null,
    );
  }

  /// Lines of a finished load (`invoice.lines`), total = `invoice.you_paid`.
  factory FeeBreakdown.forInvoice(CardInvoice inv) => FeeBreakdown(
        lines: [for (final l in inv.lines) CardFeeLine(l.label, l.amount)],
        total: inv.youPaid,
        totalLabel: 'You paid',
        footnote: inv.cardCredit > 0 ? '${money(inv.cardCredit)} added to your card' : null,
      );

  final List<CardFeeLine> lines;
  final int total;
  final String totalLabel;
  final String? footnote;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final dim = loading ? 0.45 : 1.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(14)),
      child: AnimatedOpacity(
        opacity: dim,
        duration: const Duration(milliseconds: 150),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final l in lines) _row(context, l),
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: p.border)),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Text(totalLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Text(money(total), style: X9Text.money(context, size: 20, weight: FontWeight.w700)),
          ]),
          if (footnote != null && footnote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(footnote!, textAlign: TextAlign.right, style: TextStyle(color: p.textMuted, fontSize: 12)),
            ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, CardFeeLine l) {
    final p = context.x9;
    final neg = l.amount < 0;
    final valueColor = neg ? p.statusText(X9Colors.success) : (l.muted ? p.textSecondary : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.label, style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w500)),
            if (l.note != null && l.note!.isNotEmpty) Text(l.note!, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
          ]),
        ),
        const SizedBox(width: 12),
        Text(cardSignedMoney(l.amount), style: X9Text.money(context, size: 14, color: valueColor)),
      ]),
    );
  }
}

/// Small green pill, e.g. "2% back" on the Home card tile or "Cashback" next to an offer.
class CardOfferChip extends StatelessWidget {
  const CardOfferChip(this.label, {super.key, this.icon = Icons.savings_rounded, this.dense = false, this.color});

  final String label;
  final IconData? icon;
  final bool dense;

  /// Defaults to the success green.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final c = color ?? X9Colors.success;
    final fs = dense ? 10.0 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: fs + 2, color: p.statusText(c)), const SizedBox(width: 3)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.statusText(c), fontSize: fs, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// A card offer for the user: icon, title, the headline sentence, a type chip and a start / end line.
class CardOfferTile extends StatelessWidget {
  const CardOfferTile({super.key, required this.offer});

  final CardOffer offer;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final waiver = offer.isWaiver;
    final upcoming = offer.status == 'SCHEDULED';
    final starts = offer.startsAt == null ? null : DateTime.tryParse(offer.startsAt!);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(14)),
            child: Icon(waiver ? Icons.money_off_rounded : Icons.savings_rounded, color: X9Colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(offer.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                const SizedBox(width: 6),
                CardOfferChip(upcoming ? 'Upcoming' : offer.chipText, icon: null, dense: true, color: upcoming ? X9Colors.warning : X9Colors.success),
              ]),
              const SizedBox(height: 3),
              Text(offer.headlineText, style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.3)),
              if (offer.description.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(offer.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 12)),
              ],
              const SizedBox(height: 6),
              if (upcoming && starts != null)
                Text('Starts ${fmtIst(offer.startsAt)}', style: TextStyle(color: p.statusText(X9Colors.warning), fontSize: 12, fontWeight: FontWeight.w600))
              else if (offer.endsAtTime != null)
                Countdown(target: offer.endsAtTime, prefix: 'Ends in '),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The card charges table: one row per fee rule with its value, min / max and GST.
class CardChargesTable extends StatelessWidget {
  const CardChargesTable({super.key, required this.rules});

  final List<CardFeeRule> rules;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(children: [
          for (var i = 0; i < rules.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rules[i].title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (rules[i].description.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(rules[i].description, style: TextStyle(color: p.textMuted, fontSize: 12))),
                    if (rules[i].limitsText.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(rules[i].limitsText, style: TextStyle(color: p.textMuted, fontSize: 12))),
                  ]),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(rules[i].isFlat ? cardRupees(rules[i].value.round()) : '${cardPercentText(rules[i].value)}%', style: X9Text.money(context, size: 15)),
                  Text(rules[i].gstPercent > 0 ? '+ ${cardPercentText(rules[i].gstPercent)}% GST' : 'no GST', style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                ]),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
