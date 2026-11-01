import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/location.dart';
import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/banner_carousel.dart';
import '../../widgets/bits.dart';
import '../../widgets/home_offers.dart';
import '../../widgets/home_sections.dart';
import '../lifestyle/lifestyle_screen.dart';
import '../../widgets/merchant_card.dart';
import '../../widgets/skeleton.dart';
import '../merchant/discover_screen.dart';
import '../notifications/notifications_screen.dart';
import '../pay/scan_pay.dart';
import '../payment_links/payment_links_screen.dart';
import '../wallet/wallet_screen.dart';
import 'app_drawer.dart';

/// Main screen: header (menu, city, wallet balance), banner carousel, offers, then the brands and shops
/// available in the user's city (from the central platform). Pay, transfer, card, VIP, KYC and categories live in the side bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _locating = false;
  final _offersKey = GlobalKey<HomeOffersSectionState>();
  final _recoKey = GlobalKey<HomeRecommendedState>();
  final _exploreKey = GlobalKey<HomeExploreState>();
  String? _searchCity; // city picked in "Find products & services" (null = my location)
  static bool _lifestyleAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final s = AppState.instance;
      if (s.feed == null) await s.refreshFeed();
      if (!mounted) return;
      await _locate(ask: true);
      LocationService.instance.startHeartbeat();
      unawaited(_askLifestyle());
    } catch (e, st) {
      StartupLog.error('home start', e, st); // never let start-up work throw into the zone
    }
  }

  /// First sign-in: the optional life-style form (once per app start until saved or skipped).
  Future<void> _askLifestyle() async {
    if (_lifestyleAsked || !mounted) return;
    _lifestyleAsked = true;
    try {
      final r = asMap(await Api.instance.get('/app/lifestyle'));
      if (r['needs_form'] == true && mounted) {
        await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => const LifestyleScreen(firstTime: true)));
      }
    } catch (_) {
      _lifestyleAsked = false; // try again next time Home opens
    }
  }

  Future<void> _locate({bool ask = false}) async {
    if (_locating || !mounted) return;
    setState(() => _locating = true);
    final got = await LocationService.instance.locate(mounted ? context : null, ask: ask);
    if (!mounted) return;
    setState(() => _locating = false);
    if (got) {
      await LocationService.instance.send();
      await AppState.instance.refreshFeed();
      _offersKey.currentState?.load();
      _recoKey.currentState?.load();
      _exploreKey.currentState?.load();
    }
  }

  Future<void> _refresh() async {
    _offersKey.currentState?.load();
    _recoKey.currentState?.load();
    _exploreKey.currentState?.load();
    await AppState.instance.refreshFeed();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.x9.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
      key: _scaffold,
      drawer: const AppDrawer(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _ScanFab(onTap: () => startScanPay(context)),
      body: ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) {
          final s = AppState.instance;
          final feed = s.feed;
          return RefreshIndicator(
            onRefresh: _refresh,
            edgeOffset: MediaQuery.of(context).padding.top + 60,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header(s)),
                if (feed == null && s.feedError != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorRetry(message: friendlyError(s.feedError!), onRetry: _refresh),
                  )
                else if (feed == null)
                  SliverToBoxAdapter(child: _skeleton())
                else
                  ..._content(feed),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
          );
        },
      ),
    ),
    );
  }

  Widget _header(AppState s) {
    final p = context.x9;
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(8, top + 6, 12, 12),
      decoration: BoxDecoration(color: p.background, border: Border(bottom: BorderSide(color: p.border))),
      child: Column(children: [
        Row(children: [
          Badge(
            isLabelVisible: s.unread + s.pendingLinks > 0,
            smallSize: 9,
            backgroundColor: X9Colors.primary,
            child: IconButton(
              icon: Icon(Icons.menu_rounded, color: p.text, size: 28),
              onPressed: () => _scaffold.currentState?.openDrawer(),
            ),
          ),
          Expanded(
            child: Column(children: [
              const X9Logo.mark(height: 26),
              const SizedBox(height: 4),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _locate(ask: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: p.categoryBackground, border: Border.all(color: p.categoryBorder), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _locating
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: X9Colors.primary))
                        : Icon(Icons.location_on_rounded, size: 14, color: p.categoryText),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        s.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.categoryText, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: p.categoryText),
                  ]),
                ),
              ),
            ]),
          ),
          _WalletPill(balance: s.balancesKnown ? s.clubBalance : null, onTap: () => go(context, const WalletScreen())),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => go(context, const NotificationsScreen()),
            icon: Badge(
              isLabelVisible: s.unread > 0,
              label: Text('${s.unread}'),
              child: Icon(Icons.notifications_rounded, color: p.text),
            ),
          ),
        ]),
      ]),
    );
  }

  List<Widget> _content(Map<String, dynamic> feed) {
    final banner = asMap(feed['banner']);
    final items = asList(banner['items']);
    final ratio = asDouble(banner['height_ratio']) > 0 ? asDouble(banner['height_ratio']) : 1.75 / 5.7;
    final bannerH = (MediaQuery.of(context).size.height * ratio).clamp(150.0, 420.0).toDouble();
    final brands = asList(feed['brands']);
    final cats = asList(feed['categories']);
    final bm = asMap(feed['brands_meta']);
    final nearbyCity = str(bm['nearby_city']).trim();
    final brandsFallback = bm['fallback'] == true && nearbyCity.isNotEmpty;
    final km = asDouble(bm['distance_km']);
    final nearby = asList(feed['nearby']);
    final cityName = str(asMap(feed['location'])['city']).trim();
    final where = cityName.isEmpty ? 'your city' : cityName;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: items.isNotEmpty
              ? BannerCarousel(items: items, height: bannerH)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: bannerH.clamp(150.0, 220.0).toDouble(),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(22)),
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.campaign_rounded, color: Colors.white, size: 32),
                      SizedBox(height: 8),
                      Text('Offers will show up here', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                      SizedBox(height: 4),
                      Text('Shops publish deals and videos. Check back soon.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                    ]),
                  ),
                ),
        ),
      ),
      // v6.11 order: banners+videos -> category icon grid -> search (shops/products + city) -> VIP card offers -> X9 wallet + prepaid card -> brands, offers, activity, shops
      SliverToBoxAdapter(child: HomeCategoryGrid(cats: cats)),
      SliverToBoxAdapter(
        child: HomeFindBook(
          city: _searchCity ?? (cityName.isEmpty ? '' : cityName),
          onCity: (c) => setState(() => _searchCity = c.isEmpty ? null : c),
        ),
      ),
      SliverToBoxAdapter(child: HomeBrandShowcase(items: items)),
      SliverToBoxAdapter(child: HomeWallets()),
      if (brands.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionTitle(brandsFallback ? 'Brands in $nearbyCity' : 'Brands in $where', action: 'See all', onAction: () => go(context, BrandsScreen(initial: brands))),
        ),
        if (brandsFallback)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'No brands in $where yet. Showing the nearest city with X9 brands${km > 0 ? ' (about ${km.round()} km away)' : ''}.',
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 100,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: brands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => BrandBubble(brand: asMap(brands[i])),
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(child: HomeOffersSection(key: _offersKey)),
      if (nearby.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionTitle('Merchants in $where', action: 'View all', onAction: () => go(context, DiscoverScreen(title: 'Shops in $where', cityOnly: true))),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 108,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: nearby.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => MerchantBubble(item: asMap(nearby[i])),
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(child: HomeRecommended(key: _recoKey, where: where)),
      SliverToBoxAdapter(child: HomeExplore(key: _exploreKey)),
    ];
  }

  Widget _skeleton() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Skeleton(height: (MediaQuery.of(context).size.height * 0.307).clamp(150.0, 420.0).toDouble(), radius: 22),
          const SizedBox(height: 16),
          const Skeleton(height: 86, radius: 18),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(4, (_) => const Skeleton(width: 58, height: 58, radius: 18))),
          const SizedBox(height: 20),
          const SkeletonTile(),
          const SizedBox(height: 10),
          const SkeletonTile(),
        ]),
      );
}

/// Opens the payment requests screen (also used by push notifications).
void openPaymentRequests(BuildContext context) {
  go(context, const PaymentLinksScreen());
}

class _WalletPill extends StatelessWidget {
  const _WalletPill({required this.balance, required this.onTap});
  final int? balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          decoration: BoxDecoration(
            gradient: X9Colors.heroGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: X9Colors.primary.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_wallet_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('X9 Club', style: TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.1)),
              Text(
                balance == null ? '₹ —' : money(balance, compact: true),
                style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.15, fontFeatures: X9Text.tabular),
              ),
            ]),
          ]),
        ),
      );
}

/// "Scan & Pay" pill: floats at the bottom centre and stays there while the page scrolls.
class _ScanFab extends StatelessWidget {
  const _ScanFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: X9Colors.primary.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(32)),
            child: InkWell(
              borderRadius: BorderRadius.circular(32),
              onTap: onTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Scan & Pay', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );
}
