import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../screens/merchant/merchant_screen.dart';
import '../util/helpers.dart';
import 'bits.dart';

/// One discovery result: logo, name, category, distance, best offer, rating. Tap opens the shop.
class MerchantCard extends StatelessWidget {
  const MerchantCard({super.key, required this.item});

  /// An item of GET /app/discover `results` (or feed `nearby`).
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final m = asMap(item['merchant']);
    final loc = asMap(item['location']);
    final brand = asMap(m['brand']);
    final name = str(m['shop_name'], 'Shop');
    final logo = str(m['logo_url']).isNotEmpty ? str(m['logo_url']) : str(brand['logo_url']);
    final category = nameOf(m['category']);
    final rating = asDouble(m['rating_avg']);
    final offer = offerLabel(item['best_offer'], percent: asDouble(item['max_offer_percent']));
    final dist = fmtKm(item['distance_km']);
    final sub = [if (category.isNotEmpty) category, if (str(loc['city']).isNotEmpty) str(loc['city'])].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => go(context, MerchantScreen(uuid: str(m['uuid']), distanceKm: item['distance_km'], directionsUrl: str(item['directions_url']))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            LetterAvatar(name, size: 58, url: logo),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ),
                  RatingPill(rating),
                ]),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  if (offer.isNotEmpty) Flexible(child: OfferBadge(offer)),
                  if (offer.isNotEmpty && dist.isNotEmpty) const SizedBox(width: 8),
                  if (dist.isNotEmpty) ...[
                    const Icon(Icons.near_me_rounded, size: 13, color: X9Colors.primary),
                    const SizedBox(width: 3),
                    Text(dist, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: X9Colors.primary)),
                  ],
                ]),
              ]),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: context.x9.textSecondary),
          ]),
        ),
      ),
    );
  }
}

/// Round shop logo with its name below (home strip). Tap opens the shop.
class MerchantBubble extends StatelessWidget {
  const MerchantBubble({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final m = asMap(item['merchant']);
    final brand = asMap(m['brand']);
    final name = str(m['shop_name'], 'Shop');
    final logo = str(m['logo_url']).isNotEmpty ? str(m['logo_url']) : str(brand['logo_url']);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => go(context, MerchantScreen(uuid: str(m['uuid']), distanceKm: item['distance_km'], directionsUrl: str(item['directions_url']))),
      child: SizedBox(
        width: 78,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          LetterAvatar(name, size: 62, url: logo),
          const SizedBox(height: 6),
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.15)),
        ]),
      ),
    );
  }
}
