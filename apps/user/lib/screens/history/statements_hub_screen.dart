import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import 'history_screen.dart';

/// History hub (docs/HISTORY-EXPORT-V5.md): Purchases, Payments, Prepaid card and Bank transfers, each with period chips,
/// a summary strip, the list and an Excel / PDF / TXT / CSV export. The classic Transactions screen stays linked.
class StatementsHubScreen extends StatelessWidget {
  const StatementsHubScreen({super.key});

  static const _tabs = <List<String>>[
    ['purchases', 'Purchases', 'Purchases'],
    ['payments', 'Payments', 'Payments'],
    ['card', 'Prepaid card', 'Prepaid card'],
    ['bank-transfers', 'Bank transfers', 'Bank transfers'],
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
          title: const Text('History'),
          actions: [
            IconButton(
              tooltip: 'Transactions & receipts',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => go(context, const HistoryScreen()),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in _tabs) Tab(text: t[1])],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in _tabs) StatementView(scope: StatementScope.user, statementKey: t[0], title: t[2]),
          ],
        ),
      ),
    );
  }
}
