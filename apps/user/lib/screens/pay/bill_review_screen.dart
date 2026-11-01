import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/bits.dart';
import '../../widgets/invoice_breakdown.dart';
import '../wallet/wallet_actions.dart';
import 'scan_pay.dart';
import 'upi_app_pay.dart';

/// Bill from a scanned X9 QR: merchant, items, GST, offer, final amount; pay by X9 wallet or prepaid card.
class BillReviewScreen extends StatefulWidget {
  const BillReviewScreen({super.key, required this.invoice, this.walletBalance});
  final Map<String, dynamic> invoice;
  final int? walletBalance;

  @override
  State<BillReviewScreen> createState() => _BillReviewScreenState();
}

class _BillReviewScreenState extends State<BillReviewScreen> {
  String _mode = 'WALLET';
  List<Map<String, dynamic>>? _cards;
  int? _cardId;
  late int? _balance = widget.walletBalance;
  bool _paying = false;
  Timer? _clock;

  Map<String, dynamic> get inv => widget.invoice;
  int get _final => asInt(inv['final_amount']);
  DateTime? get _expires => DateTime.tryParse(str(inv['expires_at']))?.toLocal();

  @override
  void initState() {
    super.initState();
    _loadCards();
    if (_balance == null) _loadBalance();
    AppState.instance.addListener(_onAppState);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _expires != null) setState(() {});
    });
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppState);
    _clock?.cancel();
    super.dispose();
  }

  void _onAppState() {
    final b = AppState.instance.knownClubBalance;
    if (mounted && b != null && b != _balance) setState(() => _balance = b);
  }

  Future<void> _loadCards() async {
    try {
      final c = await activeCards();
      if (mounted) setState(() => _cards = c);
    } catch (_) {
      if (mounted) setState(() => _cards = const []);
    }
  }

  Future<void> _loadBalance() async {
    await AppState.instance.refreshBalances();
    if (mounted) setState(() => _balance = AppState.instance.knownClubBalance);
  }

  bool get _walletLow => _mode == 'WALLET' && _balance != null && _balance! < _final;
  bool get _expired => _expires != null && _expires!.isBefore(DateTime.now());

  Future<void> _pay() async {
    if (_paying) return;
    if (_mode == 'CARD' && _cardId == null) {
      showError(context, 'Choose a prepaid card.');
      return;
    }
    final m = asMap(inv['merchant']);
    final shop = str(m['shop_name'], 'merchant');
    final ok = await AppLock.instance.confirm(context, reason: 'Pay ${money(_final)} to $shop');
    if (!ok || !mounted) return;
    setState(() => _paying = true);
    try {
      final r = asMap(await Api.instance.money(
        'POST',
        '/app/invoices/${inv['id']}/pay',
        {'mode': _mode, if (_mode == 'CARD') 'card_id': _cardId},
        amount: _final,
      ));
      AppState.instance.refreshBalances();
      if (!mounted) return;
      openPaymentResult(context, r, amount: _final, merchant: shop);
    } catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
      showFriendlyError(context, e);
    }
  }

  /// Pay from the phone's UPI app (bank account); the UPI auto-alert settles the bill.
  Future<void> _payUpiApp() async {
    if (_paying) return;
    final shop = str(asMap(inv['merchant'])['shop_name'], 'merchant');
    final id = inv['id'];
    final paid = await payWithUpiApp(
      context,
      intent: str(inv['upi_intent']),
      amount: _final,
      isPaid: () async => str(asMap(asMap(await Api.instance.get('/app/invoices/$id'))['invoice'])['status']).toUpperCase() == 'PAID',
      utrPath: '/app/invoices/$id/utr', // v6.18.4: "Enter UTR" when the UPI app paid but X9 has not seen it yet
    );
    if (!mounted) return;
    if (paid) {
      AppState.instance.refreshBalances();
      showOk(context, 'Paid ${money(_final)} to $shop');
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = asMap(inv['merchant']);
    final shop = str(m['shop_name'], 'Merchant');
    final offer = asInt(asMap(inv['summary'])['offer_total'] ?? inv['offer_amount']);
    final exp = _expires;
    final left = exp?.difference(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Review bill')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(24)),
          child: Column(children: [
            Row(children: [
              LetterAvatar(shop, size: 48, url: str(m['logo_url'])),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shop, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  Text('Bill ${str(inv['number'])}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ]),
              ),
              const Icon(Icons.verified_rounded, color: Colors.white),
            ]),
            const SizedBox(height: 18),
            const Text('Amount to pay', style: TextStyle(color: Colors.white70)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(money(_final), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w600, letterSpacing: -1)),
            ),
            if (offer > 0) ...[
              const SizedBox(height: 6),
              OfferBadge('You save ${money(offer)}', large: true),
            ],
            if (left != null) ...[
              const SizedBox(height: 10),
              Text(
                _expired ? 'This bill QR has expired' : 'QR valid for ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(color: _expired ? Colors.white : Colors.white70, fontSize: 12.5, fontWeight: _expired ? FontWeight.w600 : FontWeight.w500),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: InvoiceBreakdown(data: inv),
          ),
        ),
        const SectionTitle('Pay using'),
        _method(
          value: 'WALLET',
          icon: Icons.account_balance_wallet_rounded,
          title: 'X9 Club wallet',
          subtitle: _balance == null ? 'Balance loading…' : 'Balance ${money(_balance)}',
          warn: _walletLow,
        ),
        const SizedBox(height: 10),
        if (_cards == null)
          const Card(child: ListTile(leading: Icon(Icons.credit_card_rounded), title: Text('Prepaid card'), subtitle: Text('Loading cards…')))
        else
          for (final c in _cards!) ...[
            _method(
              value: 'CARD',
              cardId: asInt(c['id']),
              icon: Icons.credit_card_rounded,
              title: 'X9 prepaid card',
              subtitle: '${str(c['masked_number'], 'Card')}${c['provider_balance'] != null ? ' · ${money(asInt(c['provider_balance']))}' : ''}',
            ),
            const SizedBox(height: 10),
          ],
        if (_walletLow) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: X9Colors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: X9Colors.error),
              const SizedBox(width: 10),
              Expanded(child: Text('Your wallet is short by ${money(_final - (_balance ?? 0))}.', style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: () => startLoadWallet(context),
                child: const Text('Add money'),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _paying || _expired || _walletLow ? null : _pay,
          icon: _paying
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : const Icon(Icons.lock_rounded, size: 18),
          label: Text(_paying ? 'Paying…' : 'Pay ${money(_final)}'),
        ),
        if (str(inv['upi_intent']).isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _paying || _expired ? null : _payUpiApp,
            icon: const Icon(Icons.account_balance_rounded, size: 18),
            label: Text('Pay ${money(_final)} with UPI app (bank account)'),
          ),
        ],
        const SizedBox(height: 10),
        Text('You will be asked to unlock your phone to approve this payment.',
            textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
      ]),
    );
  }

  Widget _method({required String value, int? cardId, required IconData icon, required String title, required String subtitle, bool warn = false}) {
    final selected = _mode == value && (value != 'CARD' || _cardId == cardId);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() {
        _mode = value;
        _cardId = cardId;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? context.x9.primarySoft : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? X9Colors.primary : context.x9.border, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient:X9Colors.heroGradient, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? context.x9.text : null)),
              Text(subtitle, style: TextStyle(color: warn ? context.x9.statusText(X9Colors.error) : context.x9.textSecondary, fontSize: 12.5)),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? X9Colors.primary : context.x9.textSecondary),
        ]),
      ),
    );
  }
}
