import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/bits.dart';
import '../../widgets/offer_card.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/skeleton.dart';
import '../../services/shop_share.dart';
import '../appointments/book_appointment.dart';
import '../orders/order_sheet.dart';
import '../offers/offer_actions.dart';
import '../offers/offer_code_screen.dart';

/// Shop page: header, rating, address, directions, call; tabs Products / Services / Reviews.
class MerchantScreen extends StatefulWidget {
  const MerchantScreen({super.key, required this.uuid, this.distanceKm, this.directionsUrl});
  final String uuid;
  final dynamic distanceKm;
  final String? directionsUrl;

  @override
  State<MerchantScreen> createState() => _MerchantScreenState();
}

class _MerchantScreenState extends State<MerchantScreen> {
  Map<String, dynamic>? _d;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Api.instance.get('/app/merchants/${widget.uuid}'));
      if (mounted) {
        setState(() {
          _d = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? ErrorRetry(
                message: friendlyError(_error!),
                onRetry: () {
                  setState(() => _error = null);
                  _load();
                })
            : const SkeletonList(),
      );
    }
    final d = _d!;
    final m = asMap(d['merchant']);
    final brand = asMap(d['brand']).isNotEmpty ? asMap(d['brand']) : asMap(m['brand']);
    final logo = str(d['logo_url']).isNotEmpty ? str(d['logo_url']) : (str(m['logo_url']).isNotEmpty ? str(m['logo_url']) : str(brand['logo_url']));
    final shop = str(m['shop_name'], 'Shop');
    final locations = asList(d['locations']).map(asMap).toList();
    final loc = locations.isNotEmpty ? locations.first : const <String, dynamic>{};
    final directions = (widget.directionsUrl ?? '').isNotEmpty ? widget.directionsUrl! : str(loc['directions_url']);
    final phone = str(m['mobile']);
    final rating = asDouble(m['rating_avg']);
    final all = asList(d['products']).map(asMap).toList();
    final servicesRaw = asList(d['services']).map(asMap).toList();
    final products = all.where((p) => str(p['type']).toUpperCase() != 'SERVICE').toList();
    final services = servicesRaw.isNotEmpty ? servicesRaw : all.where((p) => str(p['type']).toUpperCase() == 'SERVICE').toList();
    final offers = asList(d['offers']).map(asMap).toList();
    final inlineReviews = asList(d['reviews']);
    final defaultOffer = asDouble(m['default_offer_percent']);
    final gallery = imageUrlsOf(d['images'] ?? m['images']);
    final promos = asList(d['promotions']).map(asMap).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 412,
              backgroundColor: X9Colors.primaryDark,
              foregroundColor: Colors.white,
              title: Text(shop),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Container(
                  decoration: const BoxDecoration(gradient: X9Colors.heroGradient),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 62),
                  child: SafeArea(
                    bottom: false,
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2.5), borderRadius: BorderRadius.circular(22)),
                          child: LetterAvatar(shop, size: 68, url: logo),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (str(brand['name']).isNotEmpty && str(brand['name']) != shop)
                              Text(str(brand['name']).toUpperCase(), style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                            Text(shop, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
                            if (nameOf(m['category']).isNotEmpty) Text(nameOf(m['category']), style: const TextStyle(color: Colors.white70)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        if (rating > 0) ...[RatingPill(rating), const SizedBox(width: 6)],
                        Text(
                          rating > 0 ? '${asInt(m['rating_count'])} reviews' : 'New on X9',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        ),
                        if (widget.distanceKm != null) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.near_me_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 3),
                          Text(fmtKm(widget.distanceKm), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ],
                        if (defaultOffer > 0) ...[const Spacer(), OfferBadge('${defaultOffer.toStringAsFixed(0)}% OFF')],
                      ]),
                      if (str(loc['address']).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(str(loc['address']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                      ],
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: _HeaderButton(
                            icon: Icons.directions_rounded,
                            label: 'Directions',
                            onTap: directions.isEmpty ? null : () => openExternal(context, directions, failMessage: 'Install Google Maps to get directions.'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HeaderButton(
                            icon: Icons.call_rounded,
                            label: 'Call',
                            onTap: phone.isEmpty ? null : () => openExternal(context, 'tel:$phone'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HeaderButton(
                            icon: Icons.local_offer_rounded,
                            label: 'Get offer',
                            filled: true,
                            onTap: () => _claim(context, null),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: _HeaderButton(
                            icon: Icons.event_available_rounded,
                            label: 'Book visit',
                            onTap: () => showBookAppointment(
                              context,
                              merchantUuid: widget.uuid,
                              shopName: shop,
                              distanceKm: widget.distanceKm,
                              locationId: intOrNull(loc['id']),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HeaderButton(
                            icon: Icons.share_rounded,
                            label: 'Share',
                            onTap: () => shareShop(context, widget.uuid),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: const ColoredBox(
                  color: X9Colors.primaryDark,
                  child: TabBar(
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    dividerColor: Colors.transparent,
                    tabs: [Tab(text: 'Products'), Tab(text: 'Services'), Tab(text: 'Reviews')],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(children: [
            _ProductList(items: products, offers: offers, gallery: gallery, promotions: promos, onClaim: (p) => _claim(context, p), onOrder: (p) => showOrderSheet(context, merchantUuid: widget.uuid, shopName: shop, product: p, distanceKm: widget.distanceKm), empty: 'No products listed yet'),
            _ProductList(items: services, offers: const [], onClaim: (p) => _claim(context, p), onOrder: (p) => showOrderSheet(context, merchantUuid: widget.uuid, shopName: shop, product: p, distanceKm: widget.distanceKm), empty: 'No services listed yet'),
            _Reviews(uuid: widget.uuid, inline: inlineReviews),
          ]),
        ),
      ),
    );
  }

  Future<void> _claim(BuildContext context, Map<String, dynamic>? product) async {
    try {
      final claim = await withProgress(
        context,
        () => fetchOfferClaim(merchantUuid: widget.uuid, productId: product == null ? null : intOrNull(product['id'])),
        label: 'Getting your code…',
      );
      if (!context.mounted) return;
      go(context, OfferCodeScreen(claim: claim));
    } catch (e) {
      if (context.mounted) showFriendlyError(context, e);
    }
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, required this.onTap, this.filled = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// White pill with red text (primary action on the red hero).
  final bool filled;

  @override
  Widget build(BuildContext context) => Material(
        color: filled ? Colors.white : Colors.white.withValues(alpha: 0.18),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: filled ? X9Colors.primaryDark : Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: filled ? X9Colors.primaryDark : Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
          ),
        ),
      );
}

/// Price after the offer: server `final_price`, else price − percent − flat.
int finalPriceOf(Map<String, dynamic> p) {
  final price = asInt(p['price'] ?? p['merchant_price']);
  if (p['final_price'] != null) return asInt(p['final_price']);
  final pct = asDouble(p['offer_percent']);
  final flat = asInt(p['offer_flat']);
  final f = price - (price * pct / 100).round() - flat;
  return f < 0 ? 0 : f;
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.items, required this.offers, required this.onClaim, required this.empty, this.onOrder, this.gallery = const [], this.promotions = const []});
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> offers;

  /// Shop photos (GET /app/merchants/{uuid} `images`).
  final List<String> gallery;

  /// Live offers of this shop (`promotions`: offer cards).
  final List<Map<String, dynamic>> promotions;
  final void Function(Map<String, dynamic> product) onClaim;
  final void Function(Map<String, dynamic> product)? onOrder;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (gallery.isNotEmpty) ...[
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: gallery.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => showImageViewer(context, gallery, initial: i),
                child: ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(width: 150, child: NetImage(gallery[i]))),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (promotions.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.only(left: 2, bottom: 8), child: Eyebrow('Live offers')),
          SizedBox(
            height: 244,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: promotions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => OfferMiniCard(card: promotions[i]),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (offers.isNotEmpty) ...[
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: offers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final o = offers[i];
                final label = offerLabel(o);
                return Container(
                  width: 230,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.x9.primarySoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: X9Colors.primary.withValues(alpha: 0.4))),
                  child: Row(children: [
                    const Icon(Icons.local_offer_rounded, color: X9Colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (label.isNotEmpty) Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(str(o['text'], str(o['name'], str(o['title']))), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.x9.textSecondary)),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (items.isEmpty) EmptyState(icon: Icons.inventory_2_outlined, title: empty),
        for (final p in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ProductTile(p: p, onClaim: () => onClaim(p), onOrder: onOrder == null ? null : () => onOrder!(p))),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.p, required this.onClaim, this.onOrder});
  final Map<String, dynamic> p;
  final VoidCallback onClaim;
  final VoidCallback? onOrder;

  @override
  Widget build(BuildContext context) {
    final price = asInt(p['price'] ?? p['merchant_price']);
    final fin = finalPriceOf(p);
    final pct = asDouble(p['offer_percent']);
    final flat = asInt(p['offer_flat']);
    final label = offerLabel({'percent': pct, 'flat': flat});
    final service = str(p['type']).toUpperCase() == 'SERVICE';
    final media = asList(p['media']);
    final gal = imageUrlsOf(p['images']);
    final img = gal.isNotEmpty
        ? gal.first
        : (str(p['image_url']).isNotEmpty ? str(p['image_url']) : (media.isNotEmpty ? str(asMap(media.first)['url'], media.first is String ? media.first as String : '') : ''));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: img.isEmpty ? null : () => showImageViewer(context, gal.isNotEmpty ? gal : [img]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 72,
                height: 72,
                child: NetImage(
                  img,
                  placeholder: Container(
                    color: context.x9.primarySoft,
                    child: Icon(service ? Icons.room_service_rounded : Icons.shopping_bag_rounded, color: X9Colors.primary, size: 30),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(p['name'], 'Item'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (str(p['description']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(str(p['description']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
                ),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(fin, compact: true), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                if (fin < price) ...[
                  const SizedBox(width: 6),
                  Text(money(price, compact: true), style: TextStyle(color: context.x9.textSecondary, decoration: TextDecoration.lineThrough, fontSize: 12.5)),
                ],
              ]),
              const SizedBox(height: 8),
              Row(children: [
                if (label.isNotEmpty) Flexible(child: OfferBadge(label)),
                const Spacer(),
                if (onOrder != null) ...[
                  SizedBox(
                    height: 34,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: onOrder,
                      icon: const Icon(Icons.shopping_bag_rounded, size: 16),
                      label: Text(service ? 'Book' : 'Order', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                SizedBox(
                  height: 34,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: context.x9.primarySoft,
                      foregroundColor: X9Colors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onClaim,
                    icon: const Icon(Icons.local_offer_rounded, size: 16),
                    label: const Text('Get offer', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Reviews extends StatelessWidget {
  const _Reviews({required this.uuid, required this.inline});
  final String uuid;
  final List<dynamic> inline;

  @override
  Widget build(BuildContext context) {
    return PagedList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      fetch: (page) async {
        try {
          return PageResult.from(await Api.instance.get('/app/merchants/$uuid/reviews', {'page': page}));
        } on ApiException catch (e) {
          if (e.status == 404 && page == 1) return PageResult(inline, false);
          rethrow;
        }
      },
      empty: const EmptyState(icon: Icons.rate_review_outlined, title: 'No reviews yet', subtitle: 'Pay with X9 and be the first to review this shop.'),
      itemBuilder: (context, r, _) {
        final u = asMap(r['user']);
        final name = str(u['name'], str(r['user_name'], 'X9 user'));
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                LetterAvatar(name, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(fmtDate(r['created_at']), style: TextStyle(color: context.x9.textSecondary, fontSize: 11.5)),
                  ]),
                ),
                RatingStars(asDouble(r['rating'])),
              ]),
              if (str(r['review']).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(str(r['review']), style: const TextStyle(height: 1.35)),
              ],
            ]),
          ),
        );
      },
    );
  }
}
