import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/location.dart';
import '../../util/helpers.dart';
import '../../widgets/offer_card.dart';
import '../../widgets/paged_list.dart';
import '../search/search_screen.dart';
import 'my_offers_screen.dart';

/// All live offers near you (GET /app/promotions): infinite scroll, pull to refresh, type filter and sort.
class OffersFeedScreen extends StatefulWidget {
  const OffersFeedScreen({super.key, this.initialType = ''});

  /// '' (all) | PRODUCT | CASHBACK
  final String initialType;

  @override
  State<OffersFeedScreen> createState() => _OffersFeedScreenState();
}

class _OffersFeedScreenState extends State<OffersFeedScreen> {
  late String _type = widget.initialType;
  String _sort = 'nearest';

  static const _types = <String, String>{'': 'All', 'PRODUCT': 'Price offers', 'CASHBACK': 'Cashback'};
  static const _sorts = <String, String>{'nearest': 'Nearest', 'ending': 'Ending soon', 'new': 'Newest'};

  Future<PageResult> _fetch(int page) async {
    final r = await Api.instance.get('/app/promotions', {
      ...LocationService.instance.query,
      if (_type.isNotEmpty) 'type': _type,
      'sort': _sort,
      'page': page,
      'per_page': 10,
    });
    return PageResult.from(r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers'),
        actions: [
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search_rounded), onPressed: () => go(context, const SearchScreen())),
          IconButton(tooltip: 'My offer codes', icon: const Icon(Icons.confirmation_number_outlined), onPressed: () => go(context, const MyOffersScreen())),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
            for (final e in _types.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
              ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: Icon(Icons.sort_rounded, size: 20, color: context.x9.textSecondary)),
            ),
            for (final e in _sorts.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(e.value), selected: _sort == e.key, showCheckmark: false, onSelected: (_) => setState(() => _sort = e.key)),
              ),
          ]),
        ),
        if (LocationService.instance.denied)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              Icon(Icons.location_off_rounded, size: 16, color: context.x9.textSecondary),
              const SizedBox(width: 6),
              Expanded(child: Text('Location is off, so offers are not sorted by distance.', style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5))),
            ]),
          ),
        Expanded(
          child: PagedList(
            key: ValueKey('$_type|$_sort'),
            fetch: _fetch,
            separator: 14,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            empty: const EmptyState(
              icon: Icons.local_offer_outlined,
              title: 'No live offers right now',
              subtitle: 'New offers from shops near you appear here. Pull down to refresh.',
            ),
            itemBuilder: (context, item, _) => OfferCard(card: item),
          ),
        ),
      ]),
    );
  }
}
