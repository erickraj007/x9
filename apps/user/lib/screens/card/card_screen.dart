import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/bits.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/skeleton.dart';
import '../kyc/kyc_entry.dart';
import '../wallet/wallet_actions.dart';
import 'card_info_sections.dart';
import 'card_limits_screen.dart';
import 'card_load_sheet.dart';
import 'card_pin_screen.dart';

/// X9 prepaid card: card visual, balance, details, PIN, limits, block/unblock, transactions.
class CardScreen extends StatefulWidget {
  const CardScreen({super.key});

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  int _index = 0;
  int? _balance;
  bool _balanceLoading = false;
  final _txKey = GlobalKey<PagedListState>();

  List<Map<String, dynamic>> get _cards =>
      asList(_data?['cards']).map(asMap).where((c) => !['CLOSED', 'INVENTORY'].contains(str(c['status']).toUpperCase())).toList();

  Map<String, dynamic>? get _card => _cards.isEmpty ? null : _cards[_index.clamp(0, _cards.length - 1)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Api.instance.get('/app/cards'));
      if (!mounted) return;
      setState(() {
        _data = r;
        _error = null;
      });
      _loadBalance();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadBalance() async {
    final c = _card;
    if (c == null) return;
    setState(() {
      _balanceLoading = true;
      _balance = c['provider_balance'] == null ? null : asInt(c['provider_balance']);
    });
    try {
      final r = asMap(await Api.instance.get('/app/cards/${c['id']}/balance'));
      if (mounted && r['provider_balance'] != null) setState(() => _balance = asInt(r['provider_balance']));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _balanceLoading = false);
    }
  }

  Future<void> _refresh() async {
    await _load();
    _txKey.currentState?.reload();
  }

  Future<void> _getVirtual() async {
    try {
      await Api.instance.post('/app/cards/virtual');
    } catch (e) {
      if (isKycRequired(e) && mounted) {
        await showKycGate(context);
        return;
      }
      rethrow;
    }
    if (!mounted) return;
    showOk(context, 'Your virtual card is being issued.');
    await _load();
  }

  /// v6.8: "Activate card" - the verified profile KYC is accepted as the card KYC.
  Future<void> _activate(Map<String, dynamic> c) async {
    try {
      await withProgress(context, () => Api.instance.post('/app/cards/${c['id']}/activate', {}));
      if (!mounted) return;
      showOk(context, 'Card is active');
      await _load();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  Future<void> _toggleBlock(Map<String, dynamic> c) async {
    final blocked = str(c['status']).toUpperCase() == 'BLOCKED';
    final action = blocked ? 'UNBLOCK' : 'BLOCK';
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(blocked ? 'Unblock card?' : 'Block card?'),
        content: Text(blocked
            ? 'Payments, ATM and online use will work again with your current limits.'
            : 'All payments with this card stop at once. You can unblock it later here.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(blocked ? 'Unblock' : 'Block')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    Api.instance.markConfirmed();
    final ok = await AppLock.instance.confirm(context, reason: blocked ? 'Unblock card' : 'Block card');
    if (!ok || !mounted) return;
    try {
      await withProgress(context, () => Api.instance.money('POST', '/app/cards/${c['id']}/status', {'action': action}, amount: 0));
      if (!mounted) return;
      showOk(context, blocked ? 'Card unblocked' : 'Card blocked');
      await _load();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  /// Add money: the v4 load sheet (live fee preview, invoice, cashback). Refreshes the card afterwards.
  Future<void> _addMoney(Map<String, dynamic> c) async {
    final loaded = await showCardLoadSheet(context, c);
    if (loaded && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('X9 prepaid card')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_data == null && _error != null && isKycRequired(_error!)) return const Center(child: UserKycGate());
    if (_data == null && _error != null) return ErrorRetry(message: friendlyError(_error!), onRetry: _load);
    if (_data == null) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        Skeleton(height: 200, radius: 22),
        SizedBox(height: 16),
        SkeletonTile(),
        SizedBox(height: 12),
        SkeletonTile(),
      ]);
    }
    final c = _card;
    if (c == null) return _noCard();
    final status = str(c['status']).toUpperCase();
    final blocked = status == 'BLOCKED';
    final active = status == 'ACTIVE';
    return PagedList(
      key: _txKey,
      fetch: (page) async {
        // microtask: never setState on this screen while the list is still building
        if (page == 1 && _data != null) unawaited(Future<void>.microtask(_loadBalance));
        return PageResult.from(await Api.instance.get('/app/cards/${c['id']}/transactions', {'page': page}));
      },
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_cards.length > 1)
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < _cards.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('•• ${str(_cards[i]['last4'], '${i + 1}')}'),
                    selected: i == _index,
                    onSelected: (_) {
                      setState(() => _index = i);
                      _loadBalance();
                      _txKey.currentState?.reload();
                    },
                  ),
                ),
            ]),
          ),
        CardVisual(card: c, holder: str(AppState.instance.user['name'], 'X9 MEMBER')),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Card balance', style: TextStyle(color: context.x9.textSecondary)),
                  const SizedBox(height: 2),
                  _balance == null && _balanceLoading
                      ? const Skeleton(width: 120, height: 26)
                      : Text(_balance == null ? '—' : money(_balance), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                ]),
              ),
              StatusChip(status),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Refresh balance',
                onPressed: _balanceLoading ? null : _loadBalance,
                icon: _balanceLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
            ]),
          ),
        ),
        if (status == 'ISSUED' || status == 'INACTIVE' || status == 'PENDING_KYC') ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your card is not active yet', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  status == 'PENDING_KYC'
                      ? 'Your KYC approval is pending. If your profile KYC is already verified, tap Activate to use it for the card.'
                      : 'Your verified profile KYC is used for the card. Tap Activate to start using it.',
                  style: TextStyle(color: context.x9.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: () => _activate(c), icon: const Icon(Icons.verified_rounded), label: const Text('Activate card')),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: ActionTile(
                    icon: Icons.add_rounded,
                    label: 'Add money',
                    onTap: active ? () => _addMoney(c) : () => _activate(c),
                  ),
                ),
                Expanded(child: ActionTile(icon: Icons.visibility_rounded, label: 'Card details', onTap: () => showCardDetails(context, c))),
                Expanded(
                  child: ActionTile(
                    icon: Icons.password_rounded,
                    label: 'Change PIN',
                    onTap: () => go(context, CardPinScreen(cardId: asInt(c['id']))),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ActionTile(
                    icon: Icons.tune_rounded,
                    label: 'Usage limits',
                    onTap: () => go(context, CardLimitsScreen(cardId: asInt(c['id']))),
                  ),
                ),
                Expanded(
                  child: ActionTile(
                    icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                    label: blocked ? 'Unblock' : 'Block card',
                    color: X9Colors.error,
                    onTap: () => _toggleBlock(c),
                  ),
                ),
                Expanded(child: ActionTile(icon: Icons.refresh_rounded, label: 'Refresh', onTap: _refresh)),
              ]),
            ]),
          ),
        ),
        const CardOffersSection(),
        const CardChargesSection(),
        const SectionTitle('Card transactions'),
      ]),
      empty: const EmptyState(icon: Icons.receipt_long_outlined, title: 'No card transactions yet', subtitle: 'Spend at shops, online or at ATMs and it shows up here.'),
      itemBuilder: (context, t, _) => CardTxnTile(t: t),
    );
  }

  Widget _noCard() {
    final kyc = str(_data?['kyc_status'], 'NOT_STARTED').toUpperCase();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Opacity(opacity: 0.5, child: CardVisual(card: const {'masked_number': 'XXXX XXXX XXXX XXXX', 'program': 'COMMON'}, holder: str(AppState.instance.user['name'], 'YOUR NAME'))),
        const SizedBox(height: 22),
        Text('Get your X9 prepaid card', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'A free virtual card for online shopping and tap-to-pay. Load it from your X9 wallet any time.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.x9.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: Icon(kyc == 'VERIFIED' ? Icons.verified_user_rounded : Icons.badge_outlined, color: kyc == 'VERIFIED' ? X9Colors.success : X9Colors.primary),
            title: const Text('Card KYC'),
            subtitle: Text(kyc == 'VERIFIED'
                ? 'Verified'
                : kyc == 'NOT_STARTED'
                    ? 'PAN and Aadhaar are needed for full card limits. Our team will help you complete it.'
                    : 'Status: ${kyc.replaceAll('_', ' ').toLowerCase()}'),
            trailing: StatusChip(kyc),
          ),
        ),
        const SizedBox(height: 18),
        BusyButton(label: 'Get virtual card', icon: Icons.add_card_rounded, onPressed: _getVirtual),
      ]),
    );
  }
}

/// Gradient card face with masked number, holder and network.
class CardVisual extends StatelessWidget {
  const CardVisual({super.key, required this.card, required this.holder});
  final Map<String, dynamic> card;
  final String holder;

  @override
  Widget build(BuildContext context) {
    final vip = str(card['program']).toUpperCase() == 'VIP';
    final masked = str(card['masked_number'], 'XXXX XXXX XXXX ${str(card['last4'], 'XXXX')}');
    final pretty = masked.replaceAll(' ', '').length == 16 ? _group(masked.replaceAll(' ', '')) : masked;
    const fg = Colors.white; // the card face is a red gradient: always white text
    final network = str(card['network'], 'RuPay');
    return AspectRatio(
      aspectRatio: 1.586,
      child: Container(
        decoration: BoxDecoration(
          gradient: vip ? const LinearGradient(colors: [X9Colors.primaryDark, X9Colors.primary], begin: Alignment.topRight, end: Alignment.bottomLeft) : X9Colors.heroGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: X9Colors.primary.withValues(alpha: 0.3), blurRadius: 26, offset: const Offset(0, 12))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned(
            right: -60,
            top: -60,
            child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07))),
          ),
          Positioned(
            left: -40,
            bottom: -80,
            child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05))),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('X9', style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(vip ? 'CLUB VIP' : 'CLUB', style: TextStyle(color: fg.withValues(alpha: 0.8), fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 12)),
                const Spacer(),
                Text(str(card['card_type'], 'VIRTUAL').toUpperCase(), style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11, letterSpacing: 1.5)),
              ]),
              const Spacer(),
              Container(
                width: 42,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.92), Colors.white.withValues(alpha: 0.6)]),
                ),
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(pretty, style: TextStyle(color: fg, fontSize: 21, letterSpacing: 2.2, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Text(holder.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                ),
                Text(network.toUpperCase(), style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, fontSize: 18)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _group(String s) => [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4 > s.length ? s.length : i + 4)].join(' ');
}

class CardTxnTile extends StatelessWidget {
  const CardTxnTile({super.key, required this.t});
  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final credit = str(t['direction']).toUpperCase() == 'CREDIT';
    final channel = str(t['channel']).toUpperCase();
    final icon = switch (channel) {
      'ATM' => Icons.local_atm_rounded,
      'POS' => Icons.point_of_sale_rounded,
      'ECOM' => Icons.shopping_cart_rounded,
      'UPI' => Icons.qr_code_rounded,
      'LOAD' => Icons.add_card_rounded,
      _ => Icons.credit_card_rounded,
    };
    return Card(
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: (credit ? X9Colors.success : X9Colors.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: credit ? X9Colors.success : X9Colors.primary),
        ),
        title: Text(str(t['description'], channel.isEmpty ? 'Card transaction' : channel), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${fmtDate(t['txn_at'])} · ${str(t['status'])}', style: const TextStyle(fontSize: 12)),
        trailing: Text('${credit ? '+' : '−'} ${money(asInt(t['amount']))}', style: TextStyle(fontWeight: FontWeight.w600, color: credit ? context.x9.statusText(X9Colors.success) : null)),
      ),
    );
  }
}

/// AppLock confirm → GET /app/cards/{id}/details (signed, amount 0) → sheet that hides itself after 30 s.
Future<void> showCardDetails(BuildContext context, Map<String, dynamic> card) async {
  final ok = await AppLock.instance.confirm(context, reason: 'Show card details');
  if (!ok || !context.mounted) return;
  Map<String, dynamic> d;
  try {
    d = asMap(await withProgress(context, () => Api.instance.money('GET', '/app/cards/${card['id']}/details', {}, amount: 0)));
  } catch (e) {
    if (context.mounted) showFriendlyError(context, e);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _CardDetailsSheet(d: d));
}

class _CardDetailsSheet extends StatefulWidget {
  const _CardDetailsSheet({required this.d});
  final Map<String, dynamic> d;

  @override
  State<_CardDetailsSheet> createState() => _CardDetailsSheetState();
}

class _CardDetailsSheetState extends State<_CardDetailsSheet> {
  int _left = 30;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Widget _row(String label, String value, {bool copy = false}) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
        subtitle: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        trailing: copy
            ? IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value.replaceAll(' ', '')));
                  showOk(context, '$label copied');
                },
              )
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final full = str(d['full_number']);
    final number = full.isNotEmpty ? CardVisual._group(full.replaceAll(' ', '')) : str(d['masked_number'], 'XXXX XXXX XXXX ${str(d['last4'])}');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Card details', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: context.x9.primarySoft, borderRadius: BorderRadius.circular(20)),
              child: Text('Hides in ${_left}s', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: context.x9.onPrimarySoft)),
            ),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: _left / 30, minHeight: 3, borderRadius: BorderRadius.circular(2)),
          const SizedBox(height: 8),
          _row('Card number', number, copy: true),
          Row(children: [
            Expanded(child: _row('Expiry', str(d['expiry'], '—'), copy: str(d['expiry']).isNotEmpty)),
            Expanded(child: _row('CVV', str(d['cvv'], '•••'))),
          ]),
          _row('Name on card', str(d['holder_name'], '—')),
          KvRow('Network', str(d['network'], '—')),
          KvRow('Type', '${str(d['card_type'], '—')} · ${str(d['program'], '')}'),
          if (asBool(d['test_mode'])) ...[
            const SizedBox(height: 8),
            const Text('Test mode: sandbox card details.', style: TextStyle(color: X9Colors.primary, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          Text('Never share your card number, CVV or PIN with anyone, including X9 staff.', style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
        ]),
      ),
    );
  }
}
