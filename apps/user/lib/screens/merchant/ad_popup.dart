import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/bits.dart';
import '../offers/offer_actions.dart';
import 'merchant_screen.dart';

/// Banner analytics (VIEW / CLICK / DIRECTIONS). Fire-and-forget.
Future<void> fireAdEvent(int id, String event) async {
  if (id <= 0) return;
  try {
    await Api.instance.post('/app/ads/$id/event', {'event': event});
  } catch (_) {}
}

/// Merchant popup for a tapped banner (GET /app/ads/{id}).
Future<void> showAdPopup(BuildContext context, Map<String, dynamic> bannerItem) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (c, scroll) => _AdPopup(item: bannerItem, scroll: scroll),
    ),
  );
}

class _AdPopup extends StatefulWidget {
  const _AdPopup({required this.item, required this.scroll});
  final Map<String, dynamic> item;
  final ScrollController scroll;

  @override
  State<_AdPopup> createState() => _AdPopupState();
}

class _AdPopupState extends State<_AdPopup> {
  Map<String, dynamic>? _d;
  bool _loading = true;

  int get _id => asInt(widget.item['id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Api.instance.get('/app/ads/$_id'));
      if (mounted) setState(() => _d = r);
    } catch (_) {
      // fall back to the banner's own data
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d ?? const <String, dynamic>{};
    final item = widget.item;
    final merchant = asMap(d['merchant']).isNotEmpty ? asMap(d['merchant']) : asMap(item['merchant']);
    final brand = asMap(d['brand']).isNotEmpty ? asMap(d['brand']) : asMap(merchant['brand']);
    final offer = asMap(d['offer']).isNotEmpty ? asMap(d['offer']) : asMap(item['offer']);
    final product = asMap(d['product']).isNotEmpty ? asMap(d['product']) : asMap(item['product']);
    final near = asMap(d['nearest_location']);
    final directions = str(d['directions_url']);
    final uuid = str(merchant['uuid']);
    final shop = str(merchant['shop_name'], str(brand['name'], 'Shop'));
    final logo = str(merchant['logo_url']).isNotEmpty ? str(merchant['logo_url']) : str(brand['logo_url']);
    final rating = asDouble(merchant['rating_avg']);
    final label = offerLabel(offer);
    final title = str(asMap(d['ad'])['title'], str(item['title']));

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(children: [
          LetterAvatar(shop, size: 64, url: logo),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (str(brand['name']).isNotEmpty && str(brand['name']) != shop)
                Text(str(brand['name']).toUpperCase(), style: TextStyle(color: context.x9.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              Text(shop, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Row(children: [
                if (rating > 0) ...[RatingStars(rating, count: asInt(merchant['rating_count'])), const SizedBox(width: 8)],
                if (near['distance_km'] != null) ...[
                  const Icon(Icons.near_me_rounded, size: 13, color: X9Colors.primary),
                  const SizedBox(width: 2),
                  Text(fmtKm(near['distance_km']), style: const TextStyle(color: X9Colors.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ],
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (label.isNotEmpty) OfferBadge(label, large: true),
            const SizedBox(height: 10),
            Text(
              str(offer['text'], title.isEmpty ? 'Exclusive X9 offer' : title),
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600, height: 1.2),
            ),
            if (title.isNotEmpty && title != str(offer['text'])) ...[
              const SizedBox(height: 4),
              Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
            ],
          ]),
        ),
        if (product.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: context.x9.primarySoft, borderRadius: BorderRadius.circular(14)),
                  child: Icon(str(product['type']).toUpperCase() == 'SERVICE' ? Icons.room_service_rounded : Icons.shopping_bag_rounded, color: X9Colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(product['name'], 'Product'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(str(product['type']).toUpperCase() == 'SERVICE' ? 'Service' : 'Product', style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (asInt(product['final_price']) > 0 && asInt(product['final_price']) < asInt(product['price']))
                    Text(
                      money(asInt(product['price']), compact: true),
                      style: TextStyle(color: context.x9.textSecondary, decoration: TextDecoration.lineThrough, fontSize: 12.5),
                    ),
                  Text(
                    money(asInt(product['final_price']) > 0 ? asInt(product['final_price']) : asInt(product['price']), compact: true),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: X9Colors.primary),
                  ),
                ]),
              ]),
            ),
          ),
        ],
        if (str(near['address']).isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.place_outlined, size: 18, color: context.x9.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${str(near['name'])}${str(near['name']).isNotEmpty ? ' · ' : ''}${str(near['address'])}', style: TextStyle(color: context.x9.textSecondary)),
            ),
          ]),
        ],
        if (_loading) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: BusyButton(
              label: 'Get offer',
              icon: Icons.local_offer_rounded,
              onPressed: () async {
                if (uuid.isEmpty) throw Exception('Shop details are still loading.');
                await claimOffer(context, merchantUuid: uuid, productId: intOrNull(product['id']), adId: _id);
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            height: 52,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(56, 52)),
              onPressed: directions.isEmpty
                  ? null
                  : () {
                      fireAdEvent(_id, 'DIRECTIONS');
                      openExternal(context, directions, failMessage: 'Install Google Maps to get directions.');
                    },
              child: const Icon(Icons.directions_rounded, color: X9Colors.primary),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: uuid.isEmpty
              ? null
              : () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute<void>(builder: (_) => MerchantScreen(uuid: uuid, distanceKm: near['distance_km'], directionsUrl: directions)));
                },
          icon: const Icon(Icons.storefront_rounded),
          label: const Text('View shop'),
        ),
      ],
    );
  }
}
