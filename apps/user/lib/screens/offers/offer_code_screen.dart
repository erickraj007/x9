import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/bits.dart';

/// Shows the 6-digit offer code the merchant enters at billing, with a live expiry countdown.
class OfferCodeScreen extends StatefulWidget {
  const OfferCodeScreen({super.key, required this.claim});

  /// POST /app/offers/claim response (or an item of GET /app/offers/claims).
  final Map<String, dynamic> claim;

  @override
  State<OfferCodeScreen> createState() => _OfferCodeScreenState();
}

class _OfferCodeScreenState extends State<OfferCodeScreen> {
  Timer? _t;
  Duration _left = Duration.zero;

  DateTime? get _expires => DateTime.tryParse(str(widget.claim['expires_at']))?.toLocal();

  @override
  void initState() {
    super.initState();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final e = _expires;
    final left = e == null ? Duration.zero : e.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _left = left.isNegative ? Duration.zero : left);
    if (left.isNegative) _t?.cancel();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String get _code => str(widget.claim['code']);

  String get _offerText {
    final o = asMap(widget.claim['offer']);
    final t = str(o['text']);
    final label = offerLabel(o);
    final product = str(o['product_name']);
    final parts = <String>[if (label.isNotEmpty && label != t) label, if (t.isNotEmpty) t, if (product.isNotEmpty) 'on $product'];
    return parts.isEmpty ? 'X9 offer' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final m = asMap(widget.claim['merchant']);
    final shop = str(m['shop_name'], 'the shop');
    final expired = _expires != null && _left == Duration.zero;
    final status = str(widget.claim['status']).toUpperCase();
    final used = status == 'REDEEMED' || status == 'USED';
    final mm = _left.inMinutes.toString().padLeft(2, '0');
    final ss = (_left.inSeconds % 60).toString().padLeft(2, '0');
    final code = _code;

    return Scaffold(
      appBar: AppBar(title: const Text('Your offer code')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            decoration: BoxDecoration(
              gradient: X9Colors.heroGradient,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: X9Colors.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Column(children: [
              Text(shop, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_offerText, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 22),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < code.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 44,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          code[i],
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            color: expired || used ? X9Colors.lightTextSecondary : X9Colors.lightText, // always on a white box
                            decoration: expired || used ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(30)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(used ? Icons.check_circle_rounded : Icons.timer_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    used
                        ? 'Code used'
                        : expired
                            ? 'Code expired'
                            : _expires == null
                                ? 'Valid for one bill'
                                : 'Expires in $mm:$ss',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: code.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: code));
                        showOk(context, 'Code copied');
                      },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: code.isEmpty || expired
                    ? null
                    : () => Share.share('My X9 offer code for $shop is $code ($_offerText). Show it at billing.'),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share code'),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('How to use', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _step(1, 'Show this code to the merchant at billing.'),
                _step(2, 'The merchant enters it in the X9 merchant app; the offer is taken off your bill.'),
                _step(3, 'Scan the bill QR with X9 and pay. One code works for one bill, within 30 minutes.'),
              ]),
            ),
          ),
          if (_expires != null) ...[
            const SizedBox(height: 8),
            KvRow('Valid until', fmtDate(widget.claim['expires_at'])),
          ],
        ]),
      ),
    );
  }

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: context.x9.primarySoft, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: X9Colors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ]),
      );
}
