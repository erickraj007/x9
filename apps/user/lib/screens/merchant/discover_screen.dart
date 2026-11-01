import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/location.dart';
import '../../util/helpers.dart';
import '../../widgets/merchant_card.dart';
import '../../widgets/skeleton.dart';

/// Category / brand / search results from GET /app/discover with sort chips.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.title, this.categoryId, this.brandId, this.search = false, this.sort = 'distance', this.cityOnly = false});
  final String title;
  final int? categoryId;
  final int? brandId;
  final bool search;
  final String sort;
  final bool cityOnly; // home "Shops in <city>": every shop of the user's city, not just the radius

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late String _sort = widget.sort;
  final _q = TextEditingController();
  Timer? _debounce;
  List<dynamic>? _results;
  Object? _error;
  int _req = 0;

  static const _sorts = {'distance': 'Nearest', 'offer': 'Best offer', 'rating': 'Top rated'};

  @override
  void initState() {
    super.initState();
    if (!widget.search) _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() => _error = null);
    try {
      final loc = LocationService.instance;
      final r = await Api.instance.get('/app/discover', {
        ...loc.query,
        if (widget.cityOnly) 'scope': 'city',
        if (widget.categoryId != null) 'category_id': widget.categoryId,
        if (widget.brandId != null) 'brand_id': widget.brandId,
        if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
        'sort': _sort,
        'limit': 100,
      });
      if (!mounted || req != _req) return;
      setState(() => _results = asList(asMap(r)['results']));
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() => _error = e);
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_q.text.trim().length >= 2 || _q.text.isEmpty) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.search
            ? TextField(
                controller: _q,
                autofocus: true,
                onChanged: _onQuery,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(
                  hintText: 'Search shops, products, brands',
                  prefixIcon: Icon(Icons.search_rounded),
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              )
            : Text(widget.title),
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final e in _sorts.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _sort == e.key,
                    onSelected: (_) {
                      setState(() => _sort = e.key);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (LocationService.instance.denied)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              Icon(Icons.location_off_rounded, size: 16, color: context.x9.textSecondary),
              SizedBox(width: 6),
              Expanded(child: Text('Location is off — distances may be missing.', style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5))),
            ]),
          ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (widget.search && _results == null && _error == null) {
      return const EmptyState(icon: Icons.search_rounded, title: 'Search X9 shops', subtitle: 'Type a shop, product or brand name.');
    }
    if (_error != null && _results == null) return ErrorRetry(message: friendlyError(_error!), onRetry: _load);
    if (_results == null) return const SkeletonList();
    final list = _results!;
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
              SizedBox(height: 40),
              EmptyState(icon: Icons.storefront_outlined, title: 'No shops found nearby', subtitle: 'Try another category or sort.'),
            ])
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => MerchantCard(item: asMap(list[i])),
            ),
    );
  }
}

/// All categories (GET /app/categories, falls back to the feed's list).
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, this.initial = const []});
  final List<dynamic> initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All categories')),
      body: AsyncView<List<dynamic>>(
        load: () async {
          try {
            final r = asList(await Api.instance.get('/app/categories'));
            return r.isEmpty ? initial : r;
          } catch (_) {
            if (initial.isNotEmpty) return initial;
            rethrow;
          }
        },
        builder: (context, cats, reload) => RefreshIndicator(
          onRefresh: reload,
          child: cats.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.category_outlined, title: 'No categories yet')])
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 92, mainAxisExtent: 104, crossAxisSpacing: 6, mainAxisSpacing: 10),
                  itemCount: cats.length,
                  itemBuilder: (_, i) {
                    final c = asMap(cats[i]);
                    return Center(
                      child: CategoryTile(
                        name: str(c['name']),
                        iconKey: str(c['icon'], str(c['slug'])),
                        iconUrl: str(c['icon_url']),
                        onTap: () => go(context, DiscoverScreen(title: str(c['name']), categoryId: intOrNull(c['id']))),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// All brands (GET /app/brands).
class BrandsScreen extends StatelessWidget {
  const BrandsScreen({super.key, this.initial = const []});
  final List<dynamic> initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Brands')),
      body: AsyncView<List<dynamic>>(
        load: () async {
          try {
            final r = asList(await Api.instance.get('/app/brands', {'city': LocationService.instance.query['city']}));
            return r.isEmpty ? initial : r;
          } catch (_) {
            if (initial.isNotEmpty) return initial;
            rethrow;
          }
        },
        builder: (context, brands, reload) => RefreshIndicator(
          onRefresh: reload,
          child: brands.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.workspace_premium_outlined, title: 'No brands yet')])
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, mainAxisExtent: 112, crossAxisSpacing: 8, mainAxisSpacing: 12),
                  itemCount: brands.length,
                  itemBuilder: (_, i) => BrandBubble(brand: asMap(brands[i])),
                ),
        ),
      ),
    );
  }
}

/// Circle brand logo with its name; tap lists the brand's shops.
class BrandBubble extends StatelessWidget {
  const BrandBubble({super.key, required this.brand});
  final Map<String, dynamic> brand;

  @override
  Widget build(BuildContext context) {
    final name = str(brand['name'], 'Brand');
    final logo = str(brand['logo_url']);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => go(context, DiscoverScreen(title: name, brandId: intOrNull(brand['id']))),
      child: SizedBox(
        width: 80,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(gradient: X9Colors.heroGradient, shape: BoxShape.circle),
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: logo.isEmpty
                  ? Center(child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: X9Colors.primary)))
                  : Padding(
                      padding: const EdgeInsets.all(6),
                      child: NetImage(logo, fit: BoxFit.contain, placeholder: const Icon(Icons.storefront_rounded, color: X9Colors.primary)),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
