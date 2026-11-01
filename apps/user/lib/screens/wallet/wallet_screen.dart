import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/bits.dart';
import '../../widgets/paged_list.dart';
import '../history/history_screen.dart';
import '../history/statements_hub_screen.dart';
import 'wallet_actions.dart';

/// X9 Club wallet: balance, actions (add money, to card, to bank, to X9 user) and statement.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _list = GlobalKey<PagedListState>();

  @override
  void initState() {
    super.initState();
    AppState.instance.refreshBalances();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('X9 Club wallet'),
        actions: [
          IconButton(
            tooltip: 'History & export',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => go(context, const StatementsHubScreen()),
          ),
          IconButton(
            tooltip: 'All transactions',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => go(context, const HistoryScreen()),
          ),
        ],
      ),
      body: PagedList(
        key: _list,
        fetch: (page) async {
          if (page == 1) AppState.instance.refreshBalances();
          return PageResult.from(await Api.instance.get('/app/ledger', {'wallet': 'USER_MAIN', 'page': page}));
        },
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListenableBuilder(listenable: AppState.instance, builder: (context, _) => _BalanceCard(state: AppState.instance)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(children: [
                Expanded(child: ActionTile(icon: Icons.add_card_rounded, label: 'Add money', onTap: () => startLoadWallet(context))),
                Expanded(child: ActionTile(icon: Icons.credit_card_rounded, label: 'To prepaid card', onTap: () => startToCard(context))),
                Expanded(child: ActionTile(icon: Icons.account_balance_rounded, label: 'To bank / UPI', onTap: () => startToBank(context))),
                Expanded(child: ActionTile(icon: Icons.person_rounded, label: 'To X9 user', onTap: () => startToUser(context))),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          const SectionTitle('Statement'),
        ]),
        empty: const EmptyState(icon: Icons.receipt_long_outlined, title: 'No wallet activity yet', subtitle: 'Add money with UPI to start paying with X9.'),
        itemBuilder: (context, line, _) => _LedgerTile(line: line),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: X9Colors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: X9Colors.primary.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Stack(children: [
        Positioned(
          right: -20,
          top: -30,
          child: Icon(Icons.account_balance_wallet_rounded, size: 140, color: Colors.white.withValues(alpha: 0.15)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('X9 CLUB', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 2)),
            const SizedBox(width: 8),
            const Text('WALLET', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, letterSpacing: 2)),
          ]),
          const SizedBox(height: 18),
          const Text('Available balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              state.balancesKnown ? money(state.clubBalance) : '₹ —',
              style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -0.5, fontFeatures: X9Text.tabular),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
            child: Text('Prepaid card: ${money(state.cardBalance)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ]),
      ]),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.line});
  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    final entry = asMap(line['entry']);
    final credit = str(line['direction']).toUpperCase() == 'CREDIT';
    final cashback = [line['type'], entry['type'], entry['entry_type']].any((t) => str(t).toUpperCase() == 'CASHBACK');
    final title = str(entry['description'], cashback ? 'Cashback' : _pretty(str(entry['entry_type'], credit ? 'Money in' : 'Money out')));
    return Card(
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: (credit ? X9Colors.success : X9Colors.error).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(cashback ? Icons.savings_rounded : (credit ? Icons.south_west_rounded : Icons.north_east_rounded), color: credit ? X9Colors.success : X9Colors.error),
        ),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Row(children: [
          if (cashback) ...[const X9ChipBadge('CASHBACK', fontSize: 10), const SizedBox(width: 6)],
          Flexible(child: Text(fmtDate(entry['posted_at'] ?? line['created_at']), style: const TextStyle(fontSize: 12))),
        ]),
        trailing: Text(
          '${credit ? '+' : '−'} ${money(asInt(line['amount']))}',
          style: TextStyle(fontWeight: FontWeight.w600, color: credit ? context.x9.statusText(X9Colors.success) : null),
        ),
      ),
    );
  }

  static String _pretty(String s) {
    if (s.isEmpty) return s;
    final t = s.replaceAll('_', ' ').toLowerCase();
    return t[0].toUpperCase() + t.substring(1);
  }
}
