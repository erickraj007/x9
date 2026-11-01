import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/paged_list.dart';
import '../payment_links/payment_links_screen.dart';

/// Inbox (GET /app/notifications); tap marks read (POST /app/notifications/read {ids}).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _list = GlobalKey<PagedListState>();
  final Set<int> _read = <int>{};

  Future<void> _markAll() async {
    try {
      await Api.instance.post('/app/notifications/read');
      AppState.instance.setUnread(0);
      if (!mounted) return;
      showOk(context, 'All notifications marked as read');
      _list.currentState?.reload();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final id = asInt(n['id']);
    final unread = n['read_at'] == null && !_read.contains(id);
    if (unread) {
      setState(() => _read.add(id));
      AppState.instance.setUnread(AppState.instance.unread - 1);
      try {
        await Api.instance.post('/app/notifications/read', {
          'ids': [id]
        });
      } catch (_) {}
    }
    final text = '${str(n['subject'])} ${str(n['body'])}'.toLowerCase();
    if (!mounted) return;
    if (text.contains('payment request') || text.contains('payment link')) {
      go(context, const PaymentLinksScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [TextButton(onPressed: _markAll, child: const Text('Mark all read'))],
      ),
      body: PagedList(
        key: _list,
        fetch: (page) async => PageResult.from(await Api.instance.get('/app/notifications', {'page': page})),
        empty: const EmptyState(icon: Icons.notifications_none_rounded, title: 'You are all caught up', subtitle: 'Payment alerts, offers and requests appear here.'),
        itemBuilder: (context, n, _) {
          final unread = n['read_at'] == null && !_read.contains(asInt(n['id']));
          return Card(
            color: unread ? context.x9.primarySoft : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _open(n),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(gradient: unread ? X9Colors.heroGradient : null, color: unread ? null : context.x9.border, shape: BoxShape.circle),
                    child: Icon(Icons.notifications_rounded, color: unread ? Colors.white : context.x9.textSecondary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(str(n['subject'], 'X9'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (str(n['body']).isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(str(n['body']), style: TextStyle(color: context.x9.textSecondary, height: 1.35)),
                      ],
                      const SizedBox(height: 6),
                      Text(fmtDate(n['created_at']), style: TextStyle(color: context.x9.textSecondary, fontSize: 11.5)),
                    ]),
                  ),
                  if (unread) Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: const BoxDecoration(color: X9Colors.primary, shape: BoxShape.circle)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
