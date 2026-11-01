import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/paged_list.dart';
import '../merchant/discover_screen.dart';
import 'offer_code_screen.dart';

/// My offer codes (GET /app/offers/claims): active ones first.
class MyOffersScreen extends StatelessWidget {
  const MyOffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My offers')),
      body: PagedList(
        fetch: (page) async => PageResult.from(await Api.instance.get('/app/offers/claims', {'page': page})),
        empty: Column(children: [
          const EmptyState(
            icon: Icons.local_offer_outlined,
            title: 'No offer codes yet',
            subtitle: 'Tap "Get offer" on a banner or a shop to get a code you can use at billing.',
          ),
          FilledButton.tonalIcon(
            onPressed: () => go(context, const DiscoverScreen(title: 'Best offers near you', sort: 'offer')),
            icon: const Icon(Icons.explore_rounded),
            label: const Text('Explore offers'),
          ),
        ]),
        itemBuilder: (context, c, _) => _ClaimTile(claim: c),
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.claim});
  final Map<String, dynamic> claim;

  @override
  Widget build(BuildContext context) {
    final m = asMap(claim['merchant']);
    final o = asMap(claim['offer']);
    final exp = DateTime.tryParse(str(claim['expires_at']))?.toLocal();
    var status = str(claim['status']).toUpperCase();
    if (status.isEmpty || status == 'ACTIVE' || status == 'ISSUED') {
      status = exp != null && exp.isBefore(DateTime.now()) ? 'EXPIRED' : 'ACTIVE';
    }
    final active = status == 'ACTIVE';
    final label = offerLabel(o);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => go(context, OfferCodeScreen(claim: claim)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 92,
              decoration: BoxDecoration(gradient: active ? X9Colors.heroGradient : null, color: active ? null : context.x9.border),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                child: Text(
                  str(claim['code'], '------'),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, letterSpacing: 1.5, color: active ? Colors.white : context.x9.textSecondary),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(str(m['shop_name'], 'Shop'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatusChip(status),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    [if (label.isNotEmpty) label, if (str(o['text']).isNotEmpty && str(o['text']) != label) str(o['text']), if (str(o['product_name']).isNotEmpty) str(o['product_name'])].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  Text('Valid until ${fmtDate(claim['expires_at'])}', style: TextStyle(color: context.x9.textSecondary, fontSize: 11.5)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
