import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/location.dart';
import '../../util/helpers.dart';
import '../../widgets/merchant_card.dart';
import '../../widgets/offer_card.dart';
import '../../widgets/skeleton.dart';
import '../../util/travel.dart';
import '../appointments/book_appointment.dart';
import '../merchant/merchant_screen.dart';

/// v6.10: search cities, shops, offers, products and services from the first letter (GET /app/search, debounced). Results are grouped.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.city, this.initialQuery = ''});

  /// v6.11: letters already typed in the home search box.
  final String initialQuery;

  /// v6.9: search another city than the one the phone is in.
  final String? city;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  int _req = 0;
  bool _loading = false;
  Object? _error;
  String _done = '';
  List<Map<String, dynamic>> _merchants = const [];
  List<Map<String, dynamic>> _offers = const [];
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _services = const [];
  List<Map<String, dynamic>> _cities = const [];
  String? _city; // a city picked from the results (overrides widget.city)
  String _sort = 'offer'; // 'offer' = offers high to low then nearest, 'distance' = nearest first

  String? get _activeCity => (_city ?? widget.city);

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      _q.text = widget.initialQuery;
      _q.selection = TextSelection.collapsed(offset: _q.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged(_q.text));
    } else {
      // v6.13: nothing typed yet -> list every shop and product, pan India, best offers / nearest first
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = asMap(await Api.instance.get(
        q.isEmpty ? '/app/browse' : '/app/search',
        {...LocationService.instance.query, if (q.isNotEmpty && (_activeCity ?? '').isNotEmpty) 'city': _activeCity, if (q.isNotEmpty) 'q': q, 'sort': _sort, 'limit': q.isEmpty ? 30 : 20},
      ));
      if (!mounted || req != _req) return;
      setState(() {
        _merchants = asList(r['merchants']).map(asMap).toList();
        _offers = asList(r['promotions']).map(asMap).toList();
        _services = asList(r['services']).map(asMap).toList();
        _products = asList(r['products']).map(asMap).where((p) => str(p['type']).toUpperCase() != 'SERVICE').toList();
        _cities = asList(r['cities']).map(asMap).toList();
        _done = q;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            _debounce?.cancel();
            _search();
          },
          decoration: InputDecoration(
            hintText: (_activeCity ?? '').isEmpty ? 'Search city, shop, product, service' : 'Search in $_activeCity',
            prefixIcon: const Icon(Icons.search_rounded),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _q.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final q = _q.text.trim();
    if (_error != null && _done.isEmpty) return ErrorRetry(message: friendlyError(_error!), onRetry: _search);
    if (_loading && _done.isEmpty) return const SkeletonList();
    final empty = _merchants.isEmpty && _offers.isEmpty && _products.isEmpty && _services.isEmpty && _cities.isEmpty;
    return Stack(children: [
      if (empty && !_loading)
        EmptyState(
          icon: Icons.search_off_rounded,
          title: q.isEmpty ? 'No shops or products yet' : 'Nothing found for "$_done"',
          subtitle: q.isEmpty ? 'New shops join every day. Pull back later.' : 'Try another spelling, a shop name or a product.',
        )
      else
        ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Offers: high to low'), selected: _sort == 'offer', onSelected: (_) => _setSort('offer')),
            ChoiceChip(label: const Text('Nearest first'), selected: _sort == 'distance', onSelected: (_) => _setSort('distance')),
          ]),
          if (q.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('All shops and products across India. Type to narrow down.', style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
            ),
          if ((_city ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.location_city_rounded, size: 18),
                label: Text('City: $_city'),
                onDeleted: () {
                  setState(() => _city = null);
                  _search();
                },
              ),
            ),
          if (_cities.isNotEmpty) ...[
            _head('Cities'),
            for (final c in _cities)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_city_rounded, color: X9Colors.primary),
                title: Text(str(c['city']), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${asInt(c['shops'])} shop${asInt(c['shops']) == 1 ? '' : 's'}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  // Search the same letters inside this city.
                  setState(() => _city = str(c['city']));
                  _search();
                },
              ),
          ],
          if (_merchants.isNotEmpty) ...[
            _head('Shops'),
            for (final m in _merchants) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ShopResult(item: m, searchCity: _activeCity)),
          ],
          if (_offers.isNotEmpty) ...[
            _head('Offers'),
            for (final o in _offers) Padding(padding: const EdgeInsets.only(bottom: 10), child: OfferRowTile(card: o)),
          ],
          if (_products.isNotEmpty) ...[
            _head('Products'),
            for (final p in _products) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ProductResult(p)),
          ],
          if (_services.isNotEmpty) ...[
            _head('Services'),
            for (final p in _services) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ProductResult(p)),
          ],
        ]),
      if (_loading) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }

  void _setSort(String v) {
    if (_sort == v) return;
    setState(() => _sort = v);
    _search();
  }

  Widget _head(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 14, 0, 8), child: Eyebrow(t));
}

class _ProductResult extends StatelessWidget {
  const _ProductResult(this.p);
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final x = context.x9;
    final shop = asMap(p['merchant']);
    final mrp = asInt(p['mrp']);
    final fin = p['final_price'] == null ? mrp : asInt(p['final_price']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: str(shop['uuid']).isEmpty ? null : () => go(context, MerchantScreen(uuid: str(shop['uuid']))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 64,
                height: 64,
                child: NetImage(str(p['image_url']), placeholder: Container(color: x.primarySoft, child: const Icon(Icons.shopping_bag_rounded, color: X9Colors.primary))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(p['name'], 'Item'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(children: [
                  Text(money(fin, compact: true), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  if (fin < mrp) ...[
                    const SizedBox(width: 6),
                    Text(money(mrp, compact: true), style: TextStyle(color: x.textSecondary, decoration: TextDecoration.lineThrough, fontSize: 12.5)),
                  ],
                ]),
                if (str(shop['shop_name']).isNotEmpty) Text(str(shop['shop_name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: x.textSecondary, fontSize: 12.5)),
                if (asDouble(p['distance_km']) > 0)
                  Text(
                    '${asDouble(p['distance_km']) < 10 ? asDouble(p['distance_km']).toStringAsFixed(1) : asDouble(p['distance_km']).round()} km · ${fmtMinutes(travelMinutes(asDouble(p['distance_km'])))}',
                    style: TextStyle(color: x.textSecondary, fontSize: 12),
                  ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: x.textSecondary),
          ]),
        ),
      ),
    );
  }
}


/// A shop result with the travel time from the phone's position and a Book visit button.
class _ShopResult extends StatelessWidget {
  const _ShopResult({required this.item, this.searchCity});
  final Map<String, dynamic> item;
  final String? searchCity;

  @override
  Widget build(BuildContext context) {
    final x = context.x9;
    final m = asMap(item['merchant']);
    final uuid = str(m['uuid']);
    final eta = etaLine(item['distance_km'], (v) => asDouble(v));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MerchantCard(item: item),
      if (eta.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Row(children: [
            Icon(Icons.directions_car_rounded, size: 16, color: x.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text(eta, style: TextStyle(color: x.textSecondary, fontSize: 12.5))),
          ]),
        ),
      if (uuid.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => showBookAppointment(
              context,
              merchantUuid: uuid,
              shopName: str(m['shop_name'], 'Shop'),
              distanceKm: item['distance_km'],
              fromCity: LocationService.instance.city,
            ),
            icon: const Icon(Icons.event_available_rounded, size: 18),
            label: const Text('Book visit'),
          ),
        ),
    ]);
  }
}
