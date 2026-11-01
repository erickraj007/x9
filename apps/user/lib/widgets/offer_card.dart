import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../screens/offers/offer_detail_screen.dart';
import '../screens/offers/offer_utils.dart';
import '../util/helpers.dart';
import 'bits.dart';

/// Opens the offer detail for a card of GET /app/promotions (counts a CLICK).
void openOffer(BuildContext context, Map<String, dynamic> card) {
  final ref = str(card['uuid'], str(card['id']));
  if (ref.isEmpty) return;
  sendPromoEvent(ref, 'CLICK');
  go(context, OfferDetailScreen(refId: ref));
}

/// Green "₹100 cashback" pill.
class CashbackBadge extends StatelessWidget {
  const CashbackBadge(this.label, {super.key, this.large = false});
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final p = context.x9;
    final fg = p.statusText(X9Colors.success);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
      decoration: BoxDecoration(color: X9Colors.success.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.savings_rounded, size: large ? 16 : 12, color: fg),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: large ? 14 : 11.5))),
      ]),
    );
  }
}

/// Small "PRICE OFFER" / "CASHBACK" tag drawn over an image.
class _TypeTag extends StatelessWidget {
  const _TypeTag(this.cashback);
  final bool cashback;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cashback ? X9Colors.success : X9Colors.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(cashback ? Icons.savings_rounded : Icons.local_offer_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(cashback ? 'CASHBACK' : 'PRICE OFFER', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ]),
      );
}

bool _isCashback(Map<String, dynamic> c) => str(c['type']).toUpperCase() == 'CASHBACK';

/// Merchant line of a card: logo, shop name, category / city, distance.
class _ShopLine extends StatelessWidget {
  const _ShopLine(this.card, {this.size = 34});
  final Map<String, dynamic> card;
  final double size;

  @override
  Widget build(BuildContext context) {
    final m = asMap(card['merchant']);
    final name = str(m['shop_name'], 'Shop');
    final sub = [nameOf(m['category']), str(m['city'])].where((s) => s.isNotEmpty).join(' · ');
    final dist = fmtKm(m['distance_km']);
    final rating = asDouble(m['rating_avg']);
    return Row(children: [
      LetterAvatar(name, size: size, url: str(m['logo_url'])),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.x9.textSecondary, fontSize: 11.5)),
        ]),
      ),
      if (rating > 0) ...[RatingPill(rating), const SizedBox(width: 8)],
      if (dist.isNotEmpty) ...[
        const Icon(Icons.near_me_rounded, size: 13, color: X9Colors.primary),
        const SizedBox(width: 2),
        Text(dist, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: X9Colors.primary)),
      ],
    ]);
  }
}

/// Offer card of the feed: image carousel, title, summary, shop, countdown, product chips (MRP to final) and cashback badge.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.card});

  /// An item of GET /app/promotions `data`.
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final cashback = _isCashback(card);
    final ends = parseTime(card['ends_at']);
    final starts = parseTime(card['starts_at']);
    final upcoming = starts != null && starts.isAfter(DateTime.now());
    final products = asList(card['products_preview']).map(asMap).toList();
    final cb = cashbackShort(card['cashback']);
    final images = imageUrlsOf(card['images']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openOffer(context, card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            ImageCarousel(urls: images, aspectRatio: 16 / 9, onTap: (_) => openOffer(context, card), placeholderIcon: cashback ? Icons.savings_rounded : Icons.local_offer_rounded),
            Positioned(left: 10, top: 10, child: _TypeTag(cashback)),
            if (cb.isNotEmpty && !cashback) Positioned(right: 10, top: 10, child: CashbackBadge(cb)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(card['title'], 'Offer'), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              if (str(card['summary']).isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(str(card['summary']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: 10),
              _ShopLine(card),
              if (products.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [for (final pr in products) _ProductChip(pr)]),
              ],
              const SizedBox(height: 10),
              Row(children: [
                if (cb.isNotEmpty) ...[CashbackBadge(cb), const SizedBox(width: 8)],
                const Spacer(),
                if (upcoming) Countdown(target: starts, prefix: 'Starts in ') else Countdown(target: ends, prefix: 'Ends in '),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "Rice 5 kg  ₹800 → ₹760" chip.
class _ProductChip extends StatelessWidget {
  const _ProductChip(this.pr);
  final Map<String, dynamic> pr;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final mrp = asInt(pr['mrp']);
    final fin = pr['final_price'] == null ? mrp : asInt(pr['final_price']);
    final img = str(pr['image_url']);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ClipOval(child: SizedBox(width: 26, height: 26, child: NetImage(img, placeholder: Container(color: p.primarySoft, child: const Icon(Icons.shopping_bag_rounded, size: 14, color: X9Colors.primary))))),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(str(pr['name'], 'Item'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        if (fin < mrp) ...[
          Text(money(mrp, compact: true), style: TextStyle(fontSize: 11, color: p.textSecondary, decoration: TextDecoration.lineThrough)),
          Icon(Icons.arrow_right_alt_rounded, size: 14, color: p.textSecondary),
        ],
        Text(money(fin, compact: true), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.statusText(X9Colors.success))),
      ]),
    );
  }
}

/// Compact vertical card for the horizontal "Live offers" strip on Home.
class OfferMiniCard extends StatelessWidget {
  const OfferMiniCard({super.key, required this.card, this.width = 250});
  final Map<String, dynamic> card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cashback = _isCashback(card);
    final m = asMap(card['merchant']);
    final ends = parseTime(card['ends_at']);
    final starts = parseTime(card['starts_at']);
    final upcoming = starts != null && starts.isAfter(DateTime.now());
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openOffer(context, card),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              ImageCarousel(urls: imageUrlsOf(card['images']).take(1).toList(), aspectRatio: 16 / 9, placeholderIcon: cashback ? Icons.savings_rounded : Icons.local_offer_rounded),
              Positioned(left: 8, top: 8, child: _TypeTag(cashback)),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(card['title'], 'Offer'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(str(card['summary']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(str(m['shop_name'], 'Shop'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  const SizedBox(width: 6),
                  if (fmtKm(m['distance_km']).isNotEmpty) Text(fmtKm(m['distance_km']), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: X9Colors.primary)),
                ]),
                const SizedBox(height: 6),
                if (upcoming) Countdown(target: starts, prefix: 'Starts in ') else Countdown(target: ends, prefix: 'Ends in '),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One-row offer for search results and "more offers from this shop".
class OfferRowTile extends StatelessWidget {
  const OfferRowTile({super.key, required this.card});
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final cashback = _isCashback(card);
    final m = asMap(card['merchant']);
    final img = imageUrlsOf(card['images']);
    final ends = parseTime(card['ends_at']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openOffer(context, card),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 76,
                height: 76,
                child: NetImage(img.isEmpty ? null : img.first, placeholder: Container(color: p.primarySoft, child: Icon(cashback ? Icons.savings_rounded : Icons.local_offer_rounded, color: X9Colors.primary, size: 30))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(card['title'], 'Offer'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                if (str(card['summary']).isNotEmpty) Text(str(card['summary']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 4),
                Row(children: [
                  Flexible(child: Text(str(m['shop_name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  if (fmtKm(m['distance_km']).isNotEmpty) Text('  ·  ${fmtKm(m['distance_km'])}', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                ]),
                const SizedBox(height: 4),
                Countdown(target: ends, prefix: 'Ends in '),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
