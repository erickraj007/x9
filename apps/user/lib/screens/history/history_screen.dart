import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/paged_list.dart';
import 'receipt_screen.dart';

/// Transactions & receipts (GET /app/history) with kind filters and the "you saved" summary.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _kind = '';
  final ValueNotifier<Map<String, dynamic>> _summary = ValueNotifier(<String, dynamic>{});

  static const _kinds = {'': 'All', 'PURCHASE': 'Payments', 'WALLET_TRANSFER': 'Transfers', 'CARD_LOAD': 'Card loads', 'TOPUP': 'Top-ups', 'PAYOUT': 'Bank', 'CASHBACK': 'Cashback'};

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  Future<PageResult> _fetch(int page) async {
    final r = asMap(await Api.instance.get('/app/history', {'page': page, if (_kind.isNotEmpty) 'kind': _kind}));
    if (page == 1) _summary.value = r;
    return PageResult.from(r['transactions'] ?? r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
        title: const Text('Transactions'),
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final e in _kinds.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(e.value), selected: _kind == e.key, onSelected: (_) => setState(() => _kind = e.key)),
                ),
            ],
          ),
        ),
        Expanded(
          child: PagedList(
            key: ValueKey(_kind),
            fetch: _fetch,
            header: ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: _summary,
              builder: (context, s, _) {
                final saved = asInt(s['offer_saved']);
                if (s.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(18)),
                    child: Row(children: [
                      const Icon(Icons.savings_rounded, color: Colors.white, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('You saved with X9', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                          Text(money(saved), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const Text('Wallet', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                        Text(money(asInt(s['wallet_balance'])), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ]),
                    ]),
                  ),
                );
              },
            ),
            empty: const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions', subtitle: 'Payments, transfers and card loads show up here.'),
            itemBuilder: (context, t, _) => TxnTile(t: t),
          ),
        ),
      ]),
    );
  }
}

class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.t});
  final Map<String, dynamic> t;

  static IconData iconFor(String kind, String mode) {
    switch (kind) {
      case 'PURCHASE':
        return Icons.storefront_rounded;
      case 'WALLET_TRANSFER':
        return Icons.swap_horiz_rounded;
      case 'CARD_LOAD':
        return Icons.credit_card_rounded;
      case 'TOPUP':
        return Icons.add_card_rounded;
      case 'PAYOUT':
        return Icons.account_balance_rounded;
      case 'CASHBACK':
        return Icons.savings_rounded;
    }
    return mode == 'UPI' ? Icons.qr_code_rounded : Icons.receipt_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final kind = str(t['kind']).toUpperCase();
    final mode = str(t['payment_mode']).toUpperCase();
    final m = asMap(t['merchant']);
    final shopName = str(m['shop_name']);
    final title = kind == 'CASHBACK'
        ? (shopName.isEmpty ? 'Cashback' : 'Cashback from $shopName')
        : str(m['shop_name'], kind.isEmpty ? 'Transaction' : '${kind[0]}${kind.substring(1).toLowerCase().replaceAll('_', ' ')}');
    final status = str(t['status']).toUpperCase();
    final offer = asInt(t['offer_amount']);
    final receipt = asMap(t['receipt']);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => go(context, ReceiptScreen(transactionId: intOrNull(t['id']), receiptId: intOrNull(receipt['id']))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: context.x9.primarySoft, borderRadius: BorderRadius.circular(14)),
              child: Icon(iconFor(kind, mode), color: X9Colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${fmtDate(t['created_at'])}${mode.isNotEmpty ? ' · $mode' : ''}', style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
                if (offer > 0) Text('Saved ${money(offer)}', style: TextStyle(color: context.x9.statusText(X9Colors.success), fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(asInt(t['final_amount'])), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 4),
              if (status != 'SUCCESS') StatusChip(status) else const Icon(Icons.check_circle_rounded, size: 16, color: X9Colors.success),
            ]),
          ]),
        ),
      ),
    );
  }
}
