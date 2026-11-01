import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/skeleton.dart';

/// My appointments with shops (request, confirmed, declined, cancelled).
class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<Map<String, dynamic>>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/app/appointments');
      if (!mounted) return;
      setState(() {
        _rows = asList(r).map(asMap).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _cancel(Map<String, dynamic> a) async {
    try {
      await withProgress(context, () => Api.instance.post('/app/appointments/${a['id']}/cancel', {}));
      await _load();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('My appointments')),
      body: rows == null
          ? (_error != null ? ErrorRetry(message: friendlyError(_error!), onRetry: _load) : const SkeletonList())
          : rows.isEmpty
              ? const EmptyState(icon: Icons.event_available_rounded, title: 'No appointments yet', subtitle: 'Open a shop or a search result and tap Book visit.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final a = rows[i];
                      final status = str(a['status']).toUpperCase();
                      final shop = asMap(a['merchant']);
                      final loc = asMap(a['location']);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(str(shop['shop_name'], 'Shop'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                              StatusChip(status),
                            ]),
                            const SizedBox(height: 4),
                            Text(fmtDate(a['scheduled_at']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (str(a['item']).isNotEmpty) Text(str(a['item'])),
                            if (str(loc['address']).isNotEmpty) Text(str(loc['address']), style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
                            if (str(a['merchant_note']).isNotEmpty) Text('Shop: ${str(a['merchant_note'])}', style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
                            if (status == 'REQUESTED' || status == 'CONFIRMED')
                              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _cancel(a), child: const Text('Cancel'))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
