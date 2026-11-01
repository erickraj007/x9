import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';

/// "Card charges" block of the Card screen: the fee table from GET /app/cards/charges.
/// Shows nothing while loading and a quiet line when the server has no charges.
class CardChargesSection extends StatefulWidget {
  const CardChargesSection({super.key});

  @override
  State<CardChargesSection> createState() => _CardChargesSectionState();
}

class _CardChargesSectionState extends State<CardChargesSection> {
  List<CardFeeRule>? _rules;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await CardApi.charges();
      if (mounted) setState(() {
        _rules = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    final p = context.x9;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Card charges'),
      if (rules == null && _error == null)
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
      else if (rules == null)
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.cloud_off_rounded, color: p.textMuted),
            title: Text(friendlyError(_error!), style: const TextStyle(fontSize: 13)),
            trailing: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        )
      else if (rules.isEmpty)
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('There are no charges on your card right now.', style: TextStyle(color: p.textSecondary)),
          ),
        )
      else ...[
        CardChargesTable(rules: rules),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text('Charges are shown before GST. The exact fee for a load is shown on the Add money screen.', style: TextStyle(color: p.textMuted, fontSize: 12)),
        ),
      ],
    ]);
  }
}

/// "Card offers" block: LIVE and upcoming offers from GET /app/cards/offers. Hidden when there are none.
class CardOffersSection extends StatefulWidget {
  const CardOffersSection({super.key});

  @override
  State<CardOffersSection> createState() => _CardOffersSectionState();
}

class _CardOffersSectionState extends State<CardOffersSection> {
  List<CardOffer> _offers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await CardApi.offers();
      if (mounted) setState(() => _offers = r);
    } catch (_) {
      // Offers are a bonus: a failure just hides the block.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_offers.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Card offers'),
      for (var i = 0; i < _offers.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        CardOfferTile(offer: _offers[i]),
      ],
    ]);
  }
}
