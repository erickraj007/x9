import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

/// Five stars for a 0–5 rating (half stars shown).
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 14, this.count, this.color, this.textColor});
  final double rating;
  final double size;
  final int? count;

  /// Star colour (default brand red); use white on a red hero card.
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          rating >= i
              ? Icons.star_rounded
              : rating >= i - 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded,
          size: size,
          color: color ?? X9Colors.primary,
        ),
      if (count != null) ...[
        const SizedBox(width: 4),
        Text('($count)', style: TextStyle(fontSize: size * 0.8, color: textColor ?? context.x9.textSecondary)),
      ],
    ]);
  }
}

/// Compact rating pill: ★ 4.3
class RatingPill extends StatelessWidget {
  const RatingPill(this.rating, {super.key});
  final double rating;

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: X9Colors.primary, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 2),
        const Icon(Icons.star_rounded, color: Colors.white, size: 12),
      ]),
    );
  }
}

/// Light-red tinted "30% OFF" badge with dark-red text (primary-light surface, primary-dark text).
class OfferBadge extends StatelessWidget {
  const OfferBadge(this.label, {super.key, this.large = false});
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final p = context.x9;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
      decoration: BoxDecoration(
        color: p.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_offer_rounded, size: large ? 15 : 11, color: p.onPrimarySoft),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.onPrimarySoft, fontWeight: FontWeight.w700, fontSize: large ? 14 : 11, letterSpacing: 0.2),
          ),
        ),
      ]),
    );
  }
}

/// Round icon button with a label underneath (quick actions). [color] is only for meaning (e.g. a
/// destructive action in [X9Colors.error]); by default the tile is a light-red tinted square with a red
/// icon. [onHero] draws it for use on top of a red gradient hero card (translucent white + white icon).
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, required this.onTap, this.badge = 0, this.color, this.onHero = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final Color? color;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final fg = onHero ? Colors.white : (color ?? X9Colors.primary);
    final bg = onHero ? Colors.white.withValues(alpha: 0.18) : (color == null ? p.primarySoft : color!.withValues(alpha: 0.12));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Badge(
            isLabelVisible: badge > 0,
            label: Text('$badge'),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: fg, size: 26),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15, color: onHero ? Colors.white : null),
          ),
        ]),
      ),
    );
  }
}

/// Label / value row used in review sheets and receipts.
class KvRow extends StatelessWidget {
  const KvRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: TextStyle(color: context.x9.textSecondary, fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.w600, fontSize: bold ? 16 : 14, color: valueColor),
            ),
          ),
        ]),
      );
}

/// Dashed divider (receipts / tickets).
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.color});

  /// Defaults to the theme border colour.
  final Color? color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final color = this.color ?? context.x9.border;
        final n = (c.maxWidth / 9).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(n, (_) => SizedBox(width: 5, height: 1.4, child: DecoratedBox(decoration: BoxDecoration(color: color)))),
        );
      });
}
