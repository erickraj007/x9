import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/bits.dart';
import '../../widgets/offer_card.dart';
import '../../widgets/skeleton.dart';
import '../merchant/merchant_screen.dart';
import 'offer_utils.dart';

/// Offer detail: image gallery, schedule and countdown, products with MRP / offer / pay balance (or the cashback
/// explainer), shop details (rating, address, call, directions, gallery), share link, other products and live offers.
/// [refId] is the offer uuid or its share code (deep links).
class OfferDetailScreen extends StatefulWidget {
  const OfferDetailScreen({super.key, required this.refId});
  final String refId;

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  Map<String, dynamic>? _d;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await loadOfferDetail(widget.refId);
      if (!mounted) return;
      setState(() {
        _d = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String get _ref {
    final promo = asMap(_d?['promotion']);
    return str(promo['uuid'], widget.refId);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Offer')),
        body: _error != null
            ? ErrorRetry(
                message: _error is ApiException && (_error as ApiException).status == 404 ? 'This offer is no longer available.' : friendlyError(_error!),
                onRetry: () {
                  setState(() => _error = null);
                  _load();
                })
            : ListView(padding: const EdgeInsets.all(16), children: const [Skeleton(height: 220, radius: 22), SizedBox(height: 16), Skeleton(height: 22), SizedBox(height: 10), Skeleton(height: 14, width: 200)]),
      );
    }
    final promo = asMap(d['promotion']);
    final shop = asMap(d['merchant']);
    final isPublic = asBool(d['public']);
    final type = str(promo['type']).toUpperCase();
    final cashbackOffer = type == 'CASHBACK';
    final status = str(promo['status'], 'LIVE').toUpperCase();
    final title = str(promo['title'], 'Offer');
    final shopName = str(shop['shop_name'], 'Shop');
    final link = asMap(promo['link']);
    final url = str(link['url']);
    final starts = parseTime(promo['starts_at']);
    final ends = parseTime(promo['ends_at']);
    final upcoming = starts != null && starts.isAfter(DateTime.now());
    final images = imageUrlsOf(promo['images']);
    final products = asList(d['products']).map(asMap).toList();
    final others = asList(d['other_products']).map(asMap).toList();
    final more = asList(d['offers_now']).map(asMap).toList();
    final locations = asList(shop['locations']).map(asMap).toList();
    final loc = locations.isNotEmpty ? locations.first : const <String, dynamic>{};
    final gallery = imageUrlsOf(shop['images']);
    final phone = str(shop['mobile']);
    final directions = str(shop['directions_url']);
    final shopUuid = str(shop['uuid']);
    final cb = asMap(promo['cashback']);
    final p = context.x9;
    final live = status == 'LIVE';

    return Scaffold(
      appBar: AppBar(
        title: Text(shopName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => shareOffer(context, ref: _ref, title: title, shop: shopName, url: url),
          ),
        ],
      ),
      bottomNavigationBar: isPublic || (directions.isEmpty && phone.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  if (phone.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          sendPromoEvent(_ref, 'CLICK');
                          openExternal(context, 'tel:$phone');
                        },
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Call'),
                      ),
                    ),
                  if (phone.isNotEmpty && directions.isNotEmpty) const SizedBox(width: 12),
                  if (directions.isNotEmpty)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          sendPromoEvent(_ref, 'CLICK');
                          openExternal(context, directions, failMessage: 'Install Google Maps to get directions.');
                        },
                        icon: const Icon(Icons.directions_rounded),
                        label: const Text('Directions'),
                      ),
                    ),
                ]),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          ImageCarousel(
            urls: images,
            radius: 22,
            aspectRatio: 16 / 10,
            placeholderIcon: cashbackOffer ? Icons.savings_rounded : Icons.local_offer_rounded,
            onTap: (i) => showImageViewer(context, images, initial: i),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: cashbackOffer ? X9Colors.success.withValues(alpha: 0.14) : p.primarySoft, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(cashbackOffer ? Icons.savings_rounded : Icons.local_offer_rounded, size: 13, color: cashbackOffer ? p.statusText(X9Colors.success) : p.onPrimarySoft),
                const SizedBox(width: 4),
                Text(cashbackOffer ? 'CASHBACK OFFER' : 'PRICE OFFER',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: cashbackOffer ? p.statusText(X9Colors.success) : p.onPrimarySoft)),
              ]),
            ),
            _StatusPill(status),
          ]),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (str(promo['description']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(str(promo['description']), style: TextStyle(color: p.textSecondary, height: 1.4)),
          ],
          if (!live && !isPublic) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: X9Colors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: X9Colors.warning),
                const SizedBox(width: 10),
                Expanded(child: Text(upcoming ? 'This offer has not started yet.' : 'This offer is not live right now.', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          _scheduleCard(context, starts, ends, upcoming),
          if (cashbackOffer) ...[
            const SizedBox(height: 14),
            _cashbackCard(context, promo, cb, products, shopName),
          ] else if (products.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.fromLTRB(2, 22, 0, 8), child: Eyebrow('Products on offer')),
            for (final pr in products) Padding(padding: const EdgeInsets.only(bottom: 10), child: _OfferProductTile(pr)),
            Text('Pay balance = MRP minus the offer. GST is charged on the pay balance at the shop.', style: TextStyle(color: p.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 8),
          const Padding(padding: EdgeInsets.fromLTRB(2, 18, 0, 8), child: Eyebrow('Shop')),
          _shopCard(context, shop, shopName, loc, shopUuid, phone, directions, isPublic),
          if (gallery.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: gallery.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => showImageViewer(context, gallery, initial: i),
                  child: ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(width: 124, child: NetImage(gallery[i]))),
                ),
              ),
            ),
          ],
          if (url.isNotEmpty) ...[
            const SizedBox(height: 18),
            _shareCard(context, url, title, shopName),
          ],
          if (others.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.fromLTRB(2, 22, 0, 8), child: Eyebrow('More from this shop')),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _OtherProductCard(others[i]),
              ),
            ),
          ],
          if (more.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(2, 22, 0, 8), child: Eyebrow('Other live offers at $shopName')),
            for (final c in more) Padding(padding: const EdgeInsets.only(bottom: 10), child: OfferRowTile(card: c)),
          ],
        ]),
      ),
    );
  }

  Widget _scheduleCard(BuildContext context, DateTime? starts, DateTime? ends, bool upcoming) {
    final p = context.x9;
    final promo = asMap(_d?['promotion']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event_available_rounded, color: p.onPrimarySoft, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Offer period', style: TextStyle(fontWeight: FontWeight.w700))),
            if (upcoming)
              Countdown(target: starts, prefix: 'Starts in ', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
            else
              Countdown(target: ends, prefix: 'Ends in ', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          KvRow('Starts', fmtIst(promo['starts_at'])),
          KvRow('Ends', fmtIst(promo['ends_at'])),
          Text('Times in Indian Standard Time', style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
        ]),
      ),
    );
  }

  Widget _cashbackCard(BuildContext context, Map<String, dynamic> promo, Map<String, dynamic> cb, List<Map<String, dynamic>> products, String shopName) {
    final short = cashbackShort(cb);
    final summary = str(promo['cashback_summary']);
    final rules = cashbackRules(cb);
    final names = products.map((e) => str(e['name'])).where((s) => s.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.savings_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Text('X9 CASHBACK', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Text(short.isNotEmpty ? short : (summary.isNotEmpty ? summary : 'Cashback'), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
        if (short.isNotEmpty && str(cb['mode']).toUpperCase() == 'PERCENT' && asInt(cb['max_cashback']) > 0)
          Text('up to ${money(asInt(cb['max_cashback']), compact: true)} per bill', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
          child: Text(
            'Pay the full bill at $shopName with X9. There is no price cut: your cashback is added to your X9 wallet as soon as the payment is complete.',
            style: const TextStyle(color: Colors.white, height: 1.4, fontSize: 13),
          ),
        ),
        if (rules.isNotEmpty || names.isNotEmpty) ...[
          const SizedBox(height: 12),
          Column(children: [
              for (final r in rules)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(r.key, style: const TextStyle(color: Colors.white70))),
                    Text(r.value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Expanded(child: Text('Valid on', style: TextStyle(color: Colors.white70))),
                  Flexible(child: Text(names.isEmpty ? 'The whole bill' : names.join(', '), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _shopCard(BuildContext context, Map<String, dynamic> shop, String name, Map<String, dynamic> loc, String shopUuid, String phone, String directions, bool isPublic) {
    final p = context.x9;
    final rating = asDouble(shop['rating_avg']);
    final address = [str(loc['address']), str(loc['city'])].where((s) => s.isNotEmpty).join(', ');
    final dist = fmtKm(loc['distance_km']);
    final brand = nameOf(shop['brand']);
    final category = nameOf(shop['category']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: shopUuid.isEmpty || isPublic ? null : () => go(context, MerchantScreen(uuid: shopUuid, distanceKm: loc['distance_km'], directionsUrl: directions)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              LetterAvatar(name, size: 56, url: str(shop['logo_url'])),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if ([brand, category].any((s) => s.isNotEmpty)) Text([brand, category].where((s) => s.isNotEmpty).join(' · '), style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                  if (rating > 0) ...[
                    const SizedBox(height: 4),
                    RatingStars(rating, count: asInt(shop['rating_count'])),
                  ],
                ]),
              ),
              if (shopUuid.isNotEmpty && !isPublic) Icon(Icons.chevron_right_rounded, color: p.textSecondary),
            ]),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.location_on_rounded, size: 18, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(address, style: TextStyle(color: p.textSecondary, height: 1.3))),
                if (dist.isNotEmpty) Text('  $dist', style: const TextStyle(fontWeight: FontWeight.w700, color: X9Colors.primary)),
              ]),
            ],
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.call_rounded, size: 18, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(fmtMobile(phone), style: TextStyle(color: p.textSecondary))),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: phone));
                    if (context.mounted) showOk(context, 'Number copied');
                  },
                  child: const Text('Copy'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _shareCard(BuildContext context, String url, String title, String shopName) {
    final p = context.x9;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          Icon(Icons.link_rounded, color: p.onPrimarySoft),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Share this offer', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) showOk(context, 'Link copied');
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => shareOffer(context, ref: _ref, title: title, shop: shopName, url: url),
          ),
        ]),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    Color c = p.textSecondary;
    IconData icon = Icons.info_outline_rounded;
    switch (status) {
      case 'LIVE':
        c = X9Colors.success;
        icon = Icons.bolt_rounded;
        break;
      case 'SCHEDULED':
        c = X9Colors.warning;
        icon = Icons.schedule_rounded;
        break;
      case 'ENDED':
      case 'SUSPENDED':
      case 'PAUSED':
        c = X9Colors.error;
        icon = Icons.pause_circle_outline_rounded;
        break;
    }
    final fg = c == p.textSecondary ? c : p.statusText(c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(status, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      ]),
    );
  }
}

/// Product row of a PRODUCT offer: image, MRP struck through, offer badge, pay balance (+ GST note).
class _OfferProductTile extends StatelessWidget {
  const _OfferProductTile(this.pr);
  final Map<String, dynamic> pr;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final mrp = asInt(pr['mrp']);
    final pay = pr['pay_balance'] != null ? asInt(pr['pay_balance']) : (pr['final_price'] != null ? asInt(pr['final_price']) : mrp);
    final label = lineOfferLabel(pr['mode'], pr['value']);
    final gst = asDouble(pr['gst_percent']);
    final saved = mrp - pay;
    final imgs = imageUrlsOf(pr['images']);
    final img = str(pr['image_url']);
    final all = imgs.isNotEmpty ? imgs : (img.isEmpty ? <String>[] : <String>[img]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: all.isEmpty ? null : () => showImageViewer(context, all),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 76,
                height: 76,
                child: NetImage(all.isEmpty ? null : all.first, placeholder: Container(color: p.primarySoft, child: const Icon(Icons.shopping_bag_rounded, color: X9Colors.primary, size: 30))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(pr['name'], 'Item'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (saved > 0) Text('MRP ${money(mrp, compact: true)}', style: TextStyle(color: p.textSecondary, decoration: TextDecoration.lineThrough, fontSize: 13)),
                if (label.isNotEmpty) OfferBadge(label),
              ]),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Pay ${money(pay, compact: true)}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: p.statusText(X9Colors.success))),
                if (gst > 0) Padding(padding: const EdgeInsets.only(left: 6, bottom: 2), child: Text('+ ${trimPct(gst)}% GST', style: TextStyle(color: p.textSecondary, fontSize: 11.5))),
              ]),
              if (saved > 0) Text('You save ${money(saved, compact: true)} per unit', style: TextStyle(color: p.textSecondary, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _OtherProductCard extends StatelessWidget {
  const _OtherProductCard(this.pr);
  final Map<String, dynamic> pr;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final mrp = asInt(pr['mrp'] ?? pr['merchant_price'] ?? pr['price']);
    final fin = pr['final_price'] == null ? mrp : asInt(pr['final_price']);
    return SizedBox(
      width: 136,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 100,
            width: double.infinity,
            child: NetImage(str(pr['image_url']), placeholder: Container(color: p.primarySoft, child: const Icon(Icons.shopping_bag_rounded, color: X9Colors.primary, size: 30))),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(pr['name'], 'Item'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Row(children: [
                Text(money(fin, compact: true), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (fin < mrp) ...[
                  const SizedBox(width: 6),
                  Flexible(child: Text(money(mrp, compact: true), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 11.5, decoration: TextDecoration.lineThrough))),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
