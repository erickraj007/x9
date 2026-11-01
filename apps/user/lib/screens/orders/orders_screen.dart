import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/skeleton.dart';

/// v6.10: my orders with shops (placed, accepted, rejected, cancelled, completed).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/app/orders');
      if (!mounted) return;
      setState(() {
        _rows = asList(r).map(asMap).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _cancel(Map<String, dynamic> o) async {
    try {
      await withProgress(context, () => Api.instance.post('/app/orders/${o['id']}/cancel', {}));
      await _load();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: rows == null
          ? (_error != null ? ErrorRetry(message: friendlyError(_error!), onRetry: _load) : const SkeletonList())
          : rows.isEmpty
              ? const EmptyState(icon: Icons.shopping_bag_outlined, title: 'No orders yet', subtitle: 'Open a shop and tap Order on a product or service.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final o = rows[i];
                      final status = str(o['status']).toUpperCase();
                      final shop = asMap(o['merchant']);
                      final addr = asMap(o['address']);
                      final items = asList(o['items']).map(asMap).toList();
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(str(shop['shop_name'], 'Shop'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                              StatusChip(status),
                            ]),
                            const SizedBox(height: 4),
                            for (final it in items) Text('${asInt(it['qty'])} × ${str(it['name'])}'),
                            const SizedBox(height: 4),
                            Text('Total ${money(asInt(o['total']), compact: true)} · ${str(o['fulfilment']) == 'PICKUP' ? 'Pick up' : 'Delivery'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (str(addr['address']).isNotEmpty) Text(str(addr['address']), style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
                            if (str(o['merchant_note']).isNotEmpty) Text('Shop: ${str(o['merchant_note'])}', style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
                            if (status == 'PLACED') Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _cancel(o), child: const Text('Cancel'))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
