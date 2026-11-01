import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/amount_entry.dart';
import '../../widgets/paged_list.dart';
import '../card/card_screen.dart';
import '../pay/scan_pay.dart';
import '../pay/upi_app_pay.dart';
import '../wallet/wallet_actions.dart';

/// Payment requests from merchants (GET /app/payment-links), paid from the X9 prepaid card.
class PaymentLinksScreen extends StatefulWidget {
  const PaymentLinksScreen({super.key});

  @override
  State<PaymentLinksScreen> createState() => _PaymentLinksScreenState();
}

class _PaymentLinksScreenState extends State<PaymentLinksScreen> {
  final _list = GlobalKey<PagedListState>();

  Future<PageResult> _fetch(int page) async {
    final r = PageResult.from(await Api.instance.get('/app/payment-links', {'page': page}));
    if (page == 1) {
      final pending = r.items.where((x) => _payable(asMap(x))).length;
      Future<void>.microtask(() => AppState.instance.setPendingLinks(pending));
    }
    return r;
  }

  static bool _payable(Map<String, dynamic> l) {
    final s = str(l['status']).toUpperCase();
    final exp = DateTime.tryParse(str(l['expires_at']));
    return (s == 'CREATED' || s == 'PENDING' || s == 'ISSUED') && (exp == null || exp.isAfter(DateTime.now()));
  }

  Future<void> _pay(Map<String, dynamic> link) async {
    List<Map<String, dynamic>> cards;
    try {
      cards = await withProgress(context, activeCards);
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
      return;
    }
    if (!mounted) return;
    if (cards.isEmpty) {
      showError(context, 'Payment requests are paid from your X9 prepaid card. Get a card first.');
      go(context, const CardScreen());
      return;
    }
    final card = cards.length == 1 ? cards.first : await pickCard(context, cards);
    if (card == null || !mounted) return;
    final amount = asInt(link['amount']);
    final m = asMap(link['merchant']);
    final shop = str(m['shop_name'], 'merchant');
    final review = await showReviewSheet(
      context,
      title: 'Pay $shop',
      amount: amount,
      rows: [
        MapEntry('To', shop),
        MapEntry('From', 'Prepaid card ${str(card['masked_number'])}'),
        if (str(link['note']).isNotEmpty) MapEntry('Note', str(link['note'])),
        if (str(link['link_id']).isNotEmpty) MapEntry('Request', str(link['link_id'])),
      ],
      confirmLabel: 'Pay ${money(amount)}',
      warning: card['provider_balance'] != null && asInt(card['provider_balance']) < amount ? 'Your card balance may be too low. Add money to the card first.' : null,
    );
    if (!review || !mounted) return;
    final ok = await AppLock.instance.confirm(context, reason: 'Pay ${money(amount)} to $shop');
    if (!ok || !mounted) return;
    try {
      final r = asMap(await withProgress(
        context,
        () => Api.instance.money('POST', '/app/payment-links/${link['id']}/pay', {'card_id': asInt(card['id'])}, amount: amount),
        label: 'Paying…',
      ));
      if (!mounted) return;
      openPaymentResult(context, r, amount: amount, merchant: shop, replace: false);
      _list.currentState?.reload();
      AppState.instance.refreshBalances();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  /// Pay a request from the phone's UPI app; confirmed automatically by the UPI auto-alert.
  Future<void> _payUpi(Map<String, dynamic> link) async {
    Map<String, dynamic> r;
    try {
      r = asMap(await withProgress(context, () => Api.instance.post('/app/payment-links/${link['id']}/upi'), label: 'Opening UPI…'));
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
      return;
    }
    if (!mounted) return;
    final amount = asInt(link['amount']);
    final shop = str(asMap(link['merchant'])['shop_name'], 'merchant');
    final paid = await payWithUpiApp(
      context,
      intent: str(r['upi_intent']),
      amount: amount,
      isPaid: () async {
        final list = asList(await Api.instance.get('/app/payment-links'));
        return list.any((x) => asInt(asMap(x)['id']) == asInt(link['id']) && str(asMap(x)['status']).toUpperCase() == 'PAID');
      },
    );
    if (!mounted) return;
    _list.currentState?.reload();
    if (paid) {
      AppState.instance.refreshBalances();
      showOk(context, 'Paid ${money(amount)} to $shop');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment requests')),
      body: PagedList(
        key: _list,
        fetch: _fetch,
        empty: const EmptyState(
          icon: Icons.request_page_outlined,
          title: 'No payment requests',
          subtitle: 'When a shop sends you a payment link, it appears here and you get a notification.',
        ),
        itemBuilder: (context, l, _) {
          final m = asMap(l['merchant']);
          final shop = str(m['shop_name'], 'Merchant');
          final payable = _payable(l);
          var status = str(l['status']).toUpperCase();
          if (!payable && (status == 'CREATED' || status == 'PENDING')) status = 'EXPIRED';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  LetterAvatar(shop, size: 46, url: str(m['logo_url'])),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(shop, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      if (str(l['note']).isNotEmpty) Text(str(l['note']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
                      Text(payable ? 'Due by ${fmtDate(l['expires_at'])}' : fmtDate(l['created_at'] ?? l['expires_at']),
                          style: TextStyle(color: context.x9.textSecondary, fontSize: 11.5)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(asInt(l['amount'])), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                    const SizedBox(height: 4),
                    StatusChip(status),
                  ]),
                ]),
                if (payable) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _pay(l),
                    icon: const Icon(Icons.credit_card_rounded, size: 18),
                    label: Text('Pay ${money(asInt(l['amount']))} with prepaid card'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _payUpi(l),
                    icon: const Icon(Icons.account_balance_rounded, size: 18),
                    label: const Text('Pay with UPI app (bank account)'),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}
