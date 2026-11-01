import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import 'bits.dart';

/// The "Prepaid card" quick action of the Home screen with a small cashback chip on top when a card
/// cashback offer is live (GET /app/cards/offers). Without a live offer it looks exactly like a plain [ActionTile].
class HomeCardTile extends StatefulWidget {
  const HomeCardTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<HomeCardTile> createState() => _HomeCardTileState();
}

class _HomeCardTileState extends State<HomeCardTile> {
  String? _chip;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final offers = await CardApi.offers();
      // Cashback first (it is what people notice), else a fee waiver; only offers that are live right now.
      CardOffer? pick;
      for (final o in offers) {
        if (!o.isLive || o.isSuspended) continue;
        if (o.isCashback) {
          pick = o;
          break;
        }
        pick ??= o;
      }
      if (mounted) setState(() => _chip = pick?.chipText);
    } catch (_) {
      // Offers are optional: no chip.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tile = ActionTile(icon: Icons.credit_card_rounded, label: 'Prepaid card', onTap: widget.onTap);
    final chip = _chip;
    if (chip == null) return tile;
    return Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
      tile,
      Positioned(top: -6, child: IgnorePointer(child: CardOfferChip(chip, dense: true))),
    ]);
  }
}
