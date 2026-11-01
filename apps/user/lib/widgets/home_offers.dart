import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../screens/offers/offers_feed_screen.dart';
import '../services/location.dart';
import '../util/helpers.dart';
import 'offer_card.dart';
import 'skeleton.dart';

/// "Live offers near you": a horizontal strip of offer cards on Home (GET /app/promotions, first page).
/// Always visible: offers, a "latest offers" fallback, an empty state or a retry card. Call [HomeOffersSectionState.load] to refresh (pull-to-refresh, new location).
class HomeOffersSection extends StatefulWidget {
  const HomeOffersSection({super.key});

  @override
  State<HomeOffersSection> createState() => HomeOffersSectionState();
}

class HomeOffersSectionState extends State<HomeOffersSection> {
  List<Map<String, dynamic>>? _items;
  bool _failed = false;
  bool _near = true;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final req = ++_req;
    try {
      var r = await Api.instance.get('/app/promotions', {...LocationService.instance.query, 'per_page': 8, 'page': 1});
      var list = asList(r).map(asMap).toList();
      var near = true;
      if (list.isEmpty && LocationService.instance.query.isNotEmpty) {
        // Nothing live close by: show the latest offers from all shops instead of an empty home.
        r = await Api.instance.get('/app/promotions', {'per_page': 8, 'page': 1});
        list = asList(r).map(asMap).toList();
        near = false;
      }
      if (!mounted || req != _req) return;
      setState(() {
        _items = list;
        _near = near;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || req != _req) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final pal = context.x9;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(_near ? 'Live offers near you' : 'Latest offers', action: 'View all', onAction: () => go(context, const OffersFeedScreen())),
      if (items == null && _failed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.wifi_off_rounded),
              title: const Text('Could not load offers'),
              subtitle: const Text('Check your connection and try again.'),
              trailing: TextButton(onPressed: () { setState(() => _failed = false); load(); }, child: const Text('Retry')),
            ),
          ),
        )
      else if (items != null && items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Icon(Icons.local_offer_rounded, size: 34, color: pal.textMuted),
                const SizedBox(height: 8),
                const Text('No live offers yet', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Shops publish offers and cashback here. Browse shops to see what is coming.', textAlign: TextAlign.center, style: TextStyle(color: pal.textSecondary, fontSize: 13)),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => go(context, const OffersFeedScreen()), child: const Text('Browse offers')),
              ]),
            ),
          ),
        )
      else if (items == null)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Skeleton(height: 210, radius: 22))
      else
        SizedBox(
          height: 244,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => OfferMiniCard(card: items[i]),
          ),
        ),
    ]);
  }
}
