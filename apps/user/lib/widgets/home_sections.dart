import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../screens/card/card_screen.dart';
import '../screens/merchant/ad_popup.dart';
import '../screens/merchant/merchant_screen.dart';
import '../util/travel.dart';
import '../services/location.dart';
import 'banner_carousel.dart' show AdPicture;
import 'merchant_card.dart';
import '../screens/history/history_screen.dart';
import '../screens/merchant/discover_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/vip/vip_screen.dart';
import '../screens/wallet/wallet_screen.dart';
import '../state/app_state.dart';
import '../util/helpers.dart';

/// v6.11 home search: (1) a box that finds shops, products and services as soon as a letter is typed, and
/// (2) a city box that suggests matching cities while typing. Both open the live search results.
class HomeFindBook extends StatefulWidget {
  const HomeFindBook({super.key, required this.city, required this.onCity});
  final String city;
  final ValueChanged<String> onCity;

  @override
  State<HomeFindBook> createState() => _HomeFindBookState();
}

class _HomeFindBookState extends State<HomeFindBook> {
  final _q = TextEditingController();
  final _cityCtl = TextEditingController();
  Timer? _debounce;
  List<String> _cities = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _cityCtl.dispose();
    super.dispose();
  }

  Future<void> _openSearch(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _q.clear();
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SearchScreen(city: widget.city.isEmpty ? null : widget.city, initialQuery: t),
    ));
  }

  void _onCityChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _cities = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = asMap(await Api.instance.get('/app/search', {'q': q, 'limit': 6}));
        if (!mounted || _cityCtl.text.trim() != q) return;
        setState(() => _cities = asList(r['cities']).map((e) => str(asMap(e)['name'], str(asMap(e)['city']))).where((e) => e.isNotEmpty).toSet().toList());
      } catch (_) {/* suggestions are optional */}
    });
  }

  void _pickCity(String c) {
    _cityCtl.clear();
    FocusScope.of(context).unfocus();
    setState(() => _cities = const []);
    widget.onCity(c);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    InputDecoration deco(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: p.textSecondary),
          suffixIcon: suffix,
          isDense: true,
          filled: true,
          fillColor: p.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.border)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _q,
          onChanged: _openSearch,
          textInputAction: TextInputAction.search,
          decoration: deco('Search shops, products, services', Icons.search_rounded),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _cityCtl,
          onChanged: _onCityChanged,
          textCapitalization: TextCapitalization.words,
          decoration: deco(
            widget.city.isEmpty ? 'Search city (type letters)' : 'City: ${widget.city} - type to change',
            Icons.location_city_rounded,
            suffix: widget.city.isEmpty ? null : IconButton(tooltip: 'Use my location', icon: const Icon(Icons.my_location_rounded), onPressed: () => widget.onCity('')),
          ),
        ),
        if (_cities.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
            child: Column(children: [
              for (final c in _cities)
                ListTile(dense: true, leading: const Icon(Icons.location_on_outlined, color: X9Colors.primary), title: Text(c), onTap: () => _pickCity(c)),
            ]),
          ),
      ]),
    );
  }
}

/// v6.11: every category as an icon grid right under the banner (4 per row, grows with the list; no limit).
class HomeCategoryGrid extends StatelessWidget {
  const HomeCategoryGrid({super.key, required this.cats});
  final List<dynamic> cats;

  @override
  Widget build(BuildContext context) {
    if (cats.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: cats.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 100),
        itemBuilder: (_, i) {
          final c = asMap(cats[i]);
          return Center(
            child: CategoryTile(
              name: str(c['name']),
              iconKey: CategoryIcon.set.containsKey(str(c['icon']).toLowerCase()) ? str(c['icon']) : (CategoryIcon.set.containsKey(str(c['slug']).toLowerCase()) ? str(c['slug']) : CategoryIcon.guess(str(c['name']))),
              iconUrl: str(c['icon_url']),
              onTap: () => go(context, DiscoverScreen(title: str(c['name']), categoryId: intOrNull(c['id']))),
            ),
          );
        },
      ),
    );
  }
}

/// Every category on the home page, in one scrolling strip (no "more categories" page needed).
class HomeCategoryStrip extends StatelessWidget {
  const HomeCategoryStrip({super.key, required this.cats});
  final List<dynamic> cats;

  @override
  Widget build(BuildContext context) {
    if (cats.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('All categories'),
      SizedBox(
        height: 104,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (_, i) {
            final c = asMap(cats[i]);
            return CategoryTile(
              name: str(c['name']),
              iconKey: CategoryIcon.set.containsKey(str(c['icon']).toLowerCase()) ? str(c['icon']) : (CategoryIcon.set.containsKey(str(c['slug']).toLowerCase()) ? str(c['slug']) : CategoryIcon.guess(str(c['name']))),
              iconUrl: str(c['icon_url']),
              onTap: () => go(context, DiscoverScreen(title: str(c['name']), categoryId: intOrNull(c['id']))),
            );
          },
        ),
      ),
    ]);
  }
}

/// v6.10: every category in a drop-down panel. Tap the header to open / close it; inside, the icons scroll down
/// (vertically) in a grid, so all categories stay on the home page without a sideways strip.
class HomeCategoryDropdown extends StatefulWidget {
  const HomeCategoryDropdown({super.key, required this.cats});
  final List<dynamic> cats;

  @override
  State<HomeCategoryDropdown> createState() => _HomeCategoryDropdownState();
}

class _HomeCategoryDropdownState extends State<HomeCategoryDropdown> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final cats = widget.cats;
    if (cats.isEmpty) return const SizedBox.shrink();
    final p = context.x9;
    // about three and a half rows are visible, so the half row shows there is more to scroll down to
    const rowH = 100.0;
    final rows = (cats.length / 4).ceil();
    final height = (rows <= 3 ? rows * rowH : rowH * 3.5) + 8;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)),
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                const Icon(Icons.apps_rounded, color: X9Colors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('All categories (${cats.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                AnimatedRotation(turns: _open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.keyboard_arrow_down_rounded, size: 28)),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: height,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: cats.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: rowH),
                      itemBuilder: (_, i) {
                        final c = asMap(cats[i]);
                        return Center(
                          child: CategoryTile(
                            name: str(c['name']),
                            iconKey: CategoryIcon.set.containsKey(str(c['icon']).toLowerCase()) ? str(c['icon']) : (CategoryIcon.set.containsKey(str(c['slug']).toLowerCase()) ? str(c['slug']) : CategoryIcon.guess(str(c['name']))),
                            iconUrl: str(c['icon_url']),
                            onTap: () => go(context, DiscoverScreen(title: str(c['name']), categoryId: intOrNull(c['id']))),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// X9 wallet and prepaid card wallet side by side.
class HomeWallets extends StatelessWidget {
  const HomeWallets({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    Widget tile(IconData icon, String label, String value, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(height: 10),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('My wallets'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          tile(Icons.account_balance_wallet_rounded, 'X9 Club wallet', s.balancesKnown ? money(s.clubBalance, compact: true) : '₹ —', () => go(context, const WalletScreen())),
          const SizedBox(width: 12),
          tile(Icons.credit_card_rounded, 'Prepaid card wallet', s.balancesKnown ? money(s.cardBalance, compact: true) : '₹ —', () => go(context, const CardScreen())),
        ]),
      ),
    ]);
  }
}

/// X9 VIP Club and VIP card benefits (from the live plans), with Join / View.
class HomeVipBenefits extends StatefulWidget {
  const HomeVipBenefits({super.key});

  @override
  State<HomeVipBenefits> createState() => _HomeVipBenefitsState();
}

class _HomeVipBenefitsState extends State<HomeVipBenefits> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Api.instance.get('/app/vip'));
      if (mounted) setState(() => _d = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final isVip = asBool(d['is_vip']);
    final plans = asList(d['plans']).map(asMap).toList();
    final benefits = <String>[];
    for (final p in plans) {
      for (final b in asList(p['benefits'])) {
        final t = b is Map ? str(b['title'] ?? b['name'] ?? b['text']) : str(b);
        if (t.isNotEmpty && !benefits.contains(t)) benefits.add(t);
      }
    }
    final p = context.x9;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('X9 VIP Club & VIP card', action: isVip ? 'View' : 'Join', onAction: () => go(context, const VipScreen())),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: X9Colors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(isVip ? 'You are a VIP member' : 'Become a VIP member', style: const TextStyle(fontWeight: FontWeight.w700))),
              if (!isVip && plans.isNotEmpty) Text('from ${money(plans.map((x) => asInt(x['price'])).reduce((a, b) => a < b ? a : b), compact: true)}', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
            ]),
            const SizedBox(height: 8),
            if (benefits.isEmpty)
              Text('Extra offers, cashback and the X9 VIP card.', style: TextStyle(color: p.textSecondary))
            else
              for (final b in benefits.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_circle_rounded, size: 16, color: X9Colors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b, style: const TextStyle(fontSize: 13.5))),
                  ]),
                ),
          ]),
        ),
      ),
    ]);
  }
}

/// Latest transactions and invoices (tap one for the receipt / invoice).
class HomeRecentActivity extends StatefulWidget {
  const HomeRecentActivity({super.key});

  @override
  State<HomeRecentActivity> createState() => HomeRecentActivityState();
}

class HomeRecentActivityState extends State<HomeRecentActivity> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await Api.instance.get('/app/history', {'page': 1}));
      final t = r['transactions'] ?? r;
      final list = asList(t is Map ? t['data'] : t).map(asMap).take(5).toList();
      if (mounted) setState(() => _rows = list);
    } catch (_) {
      if (mounted) setState(() => _rows ??= const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Transactions & invoices', action: 'View all', onAction: () => go(context, const HistoryScreen())),
      if (rows == null)
        const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(minHeight: 2))
      else if (rows.isEmpty)
        const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions yet', subtitle: 'Payments, invoices and receipts show up here.')
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [for (final t in rows) TxnTile(t: t)]),
        ),
    ]);
  }
}


/// v6.13: paid brands (merchants and screens) pushed from the central portal: brand logo or product picture with the offer.
/// Tap a tile for the details (shop, product, offer, directions). Reads the same live ads as the banner carousel.
class HomeBrandShowcase extends StatelessWidget {
  const HomeBrandShowcase({super.key, required this.items});
  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    // one tile per shop (its newest ad)
    final seen = <String>{};
    final tiles = <Map<String, dynamic>>[];
    for (final e in items) {
      final it = asMap(e);
      final key = str(asMap(it['merchant'])['uuid'], '${it['id']}');
      if (seen.add(key)) tiles.add(it);
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    final p = context.x9;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Featured brands & products'),
      SizedBox(
        height: 196,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: tiles.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final it = tiles[i];
            final m = asMap(it['merchant']);
            final brand = asMap(m['brand']);
            final prod = asMap(it['product']);
            final offer = asMap(it['offer']);
            final isImage = str(it['type']).toUpperCase() == 'IMAGE';
            final logo = str(m['logo_url']).isNotEmpty ? str(m['logo_url']) : str(brand['logo_url']);
            final name = str(m['shop_name'], str(it['title']));
            final line = prod.isNotEmpty ? str(prod['name']) : str(offer['text'], str(it['title']));
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => showAdPopup(context, it),
              child: Container(
                width: 150,
                decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    height: 108,
                    child: isImage
                        ? AdPicture(id: asInt(it['id']), signedUrl: str(it['media_url']))
                        : Container(color: p.primarySoft, alignment: Alignment.center, child: LetterAvatar(name, size: 64, url: logo)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12, height: 1.25)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// v6.13: "Recommended for you": shops like the ones the person already pays at, nearest first, pan India (GET /app/recommended).
class HomeRecommended extends StatefulWidget {
  const HomeRecommended({super.key, required this.where});
  final String where;

  @override
  State<HomeRecommended> createState() => HomeRecommendedState();
}

class HomeRecommendedState extends State<HomeRecommended> {
  List<Map<String, dynamic>>? _shops;
  bool _usage = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await Api.instance.get('/app/recommended', {...LocationService.instance.query, 'limit': 12}));
      if (!mounted) return;
      setState(() {
        _shops = asList(r['shops']).map(asMap).toList();
        _usage = asBool(r['based_on_usage']);
      });
    } catch (_) {
      if (mounted) setState(() => _shops ??= const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = _shops;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(
        'Recommended for you',
        action: 'View all',
        onAction: () => go(context, const SearchScreen()),
      ),
      if (shops != null && shops.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(_usage ? 'Shops like the ones you use, nearest first.' : 'Nearest shops first.', style: TextStyle(fontSize: 12.5, color: context.x9.textSecondary)),
        ),
      if (shops == null)
        const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(minHeight: 2))
      else if (shops.isEmpty)
        const EmptyState(icon: Icons.storefront_outlined, title: 'No X9 shops yet', subtitle: 'New shops join every day. Pull down to refresh.')
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [for (final s in shops) Padding(padding: const EdgeInsets.only(bottom: 10), child: MerchantCard(item: s))]),
        ),
    ]);
  }
}


/// v6.13: bottom of the home page - scroll down to see every offer, brand and product picture (shops and products pan India,
/// best offers first, then nearest). Loads 20 more as the person reaches the end (GET /app/browse?page=n).
class HomeExplore extends StatefulWidget {
  const HomeExplore({super.key});

  @override
  State<HomeExplore> createState() => HomeExploreState();
}

class HomeExploreState extends State<HomeExplore> {
  final List<Map<String, dynamic>> _tiles = [];
  int _page = 0;
  bool _loading = false;
  bool _more = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  /// Restart from the first page (pull to refresh, new location).
  Future<void> load() async {
    _tiles.clear();
    _page = 0;
    _more = true;
    _failed = false;
    await _next();
  }

  Future<void> _next() async {
    if (_loading || !_more) return;
    setState(() => _loading = true);
    try {
      final r = asMap(await Api.instance.get('/app/browse', {...LocationService.instance.query, 'sort': 'offer', 'limit': 20, 'page': _page + 1}));
      final shops = asList(r['merchants']).map(asMap).toList();
      final prods = asList(r['products']).map(asMap).toList();
      // interleave shops and products so brands and products mix
      final added = <Map<String, dynamic>>[];
      for (var i = 0; i < (shops.length > prods.length ? shops.length : prods.length); i++) {
        if (i < prods.length) added.add({'kind': 'product', ...prods[i]});
        if (i < shops.length) added.add({'kind': 'shop', ...shops[i]});
      }
      if (!mounted) return;
      setState(() {
        _page++;
        _tiles.addAll(added);
        _more = shops.length >= 20 || prods.length >= 20;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _more = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('All offers, brands & products'),
      if (_tiles.isEmpty && _loading) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(minHeight: 2)),
      if (_tiles.isEmpty && !_loading)
        EmptyState(
          icon: Icons.storefront_outlined,
          title: _failed ? 'Could not load' : 'Nothing here yet',
          subtitle: _failed ? 'Pull down to try again.' : 'Offers, brands and products show up here as shops join.',
        ),
      if (_tiles.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _tiles.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 214),
            itemBuilder: (context, i) {
              if (i >= _tiles.length - 2 && _more && !_loading) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _next();
                });
              }
              return _ExploreTile(t: _tiles[i], palette: p);
            },
          ),
        ),
      if (_loading && _tiles.isNotEmpty) const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
    ]);
  }
}

class _ExploreTile extends StatelessWidget {
  const _ExploreTile({required this.t, required this.palette});
  final Map<String, dynamic> t;
  final dynamic palette;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final product = str(t['kind']) == 'product';
    final m = asMap(t['merchant']);
    final km = asDouble(t['distance_km']);
    final dist = km > 0 ? '${km < 10 ? km.toStringAsFixed(1) : km.round()} km · ${fmtMinutes(travelMinutes(km))}' : '';
    String? badge;
    String title;
    String sub;
    Widget picture;
    if (product) {
      final pct = asDouble(t['offer_percent']);
      badge = pct > 0 ? '${pct.round()}% OFF' : null;
      title = str(t['name'], 'Item');
      final mrp = asInt(t['mrp']);
      final fin = t['final_price'] == null ? mrp : asInt(t['final_price']);
      sub = '${money(fin, compact: true)}${fin < mrp ? '  ' : ''}${fin < mrp ? money(mrp, compact: true) : ''}  ·  ${str(m['shop_name'])}';
      picture = NetImage(str(t['image_url']), placeholder: Container(color: p.primarySoft, child: const Icon(Icons.shopping_bag_rounded, color: X9Colors.primary, size: 36)));
    } else {
      final brand = asMap(m['brand']);
      final logo = str(m['logo_url']).isNotEmpty ? str(m['logo_url']) : str(brand['logo_url']);
      final pct = asDouble(t['max_offer_percent']);
      badge = pct > 0 ? '${pct.round()}% OFF' : null;
      title = str(m['shop_name'], 'Shop');
      sub = str(asMap(t['best_offer'])['text'], str(asMap(t['location'])['city']));
      picture = Container(color: p.primarySoft, alignment: Alignment.center, child: LetterAvatar(title, size: 72, url: logo));
    }
    final uuid = str(m['uuid']);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: uuid.isEmpty ? null : () => go(context, MerchantScreen(uuid: uuid, distanceKm: t['distance_km'], directionsUrl: str(t['directions_url']))),
      child: Container(
        decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 116,
            child: Stack(fit: StackFit.expand, children: [
              picture,
              if (badge != null)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: X9Colors.primary, borderRadius: BorderRadius.circular(10)),
                    child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12, height: 1.25)),
              if (dist.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(dist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
