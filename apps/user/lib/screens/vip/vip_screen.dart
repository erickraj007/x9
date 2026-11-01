import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/upi_qr.dart';
import '../kyc/kyc_entry.dart';
import '../profile/profile_screen.dart';
import 'vip_models.dart';

/// X9 VIP Club: status, plans with price and benefits, "Join VIP Club" (dynamic UPI QR, paid with any UPI app).
class VipScreen extends StatefulWidget {
  const VipScreen({super.key});

  @override
  State<VipScreen> createState() => _VipScreenState();
}

class _VipScreenState extends State<VipScreen> {
  VipStatus? _s;
  Object? _error;
  int? _planId;
  String _tier = 'VIP';
  final _refCtl = TextEditingController();
  bool _refBusy = false;
  bool _busy = false;

  @override
  void dispose() {
    _refCtl.dispose();
    super.dispose();
  }

  Future<void> _saveReferral() async {
    final code = _refCtl.text.trim();
    if (code.isEmpty || _refBusy) return;
    setState(() => _refBusy = true);
    try {
      await Api.instance.post('/app/vip/referral', {'code': code});
      _refCtl.clear();
      await _load();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
    if (mounted) setState(() => _refBusy = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = VipStatus.fromJson(await Api.instance.get('/app/vip'));
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = null;
        if (_planId == null || !s.plans.any((p) => p.id == _planId)) {
          final first = s.plans.where((p) => p.tier == _tier);
          _planId = first.isNotEmpty ? first.first.id : (s.plans.isEmpty ? null : s.plans.first.id);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  VipPlan? get _plan {
    final s = _s;
    if (s == null) return null;
    for (final p in s.plans) {
      if (p.id == _planId) return p;
    }
    return null;
  }

  Future<void> _join() async {
    final plan = _plan;
    final s = _s;
    if (plan == null || s == null || _busy) return;
    if (s.kycStatus.isNotEmpty && !s.kycVerified) {
      await showKycGate(context);
      return;
    }
    final unlocked = await AppLock.instance.confirm(context, reason: 'Join VIP Club for ${money(plan.price)}');
    if (!unlocked || !mounted) return;
    setState(() => _busy = true);
    try {
      final key = SessionStore.newIdempotencyKey();
      final r = asMap(await Api.instance.money('POST', '/app/vip/purchase', {'plan_id': plan.id}, amount: plan.price, idempotencyKey: key));
      if (!mounted) return;
      setState(() => _busy = false);
      await go<void>(context, VipPayScreen(purchase: r));
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showFriendlyError(context, e);
    }
  }

  Future<void> _resume(Map<String, dynamic> purchase) async {
    await go<void>(context, VipPayScreen(purchase: purchase));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('X9 VIP Club')),
      body: s == null && _error == null
          ? const SkeletonList(count: 3)
          : s == null
              ? ErrorRetry(message: friendlyError(_error!), onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _content(context, s)),
    );
  }

  Widget _content(BuildContext context, VipStatus s) {
    final p = context.x9;
    final pending = s.purchase;
    final pendingActive = pending != null &&
        vipPurchaseStatus(pending) == 'PENDING' &&
        !vipExpired(str(pending['expires_at'])) &&
        (str(pending['purchase_id']).isNotEmpty || str(pending['id']).isNotEmpty);
    return ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.isVip ? 'You are a VIP member' : 'Become a VIP member',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                s.isVip
                    ? (s.vipSince == null ? 'Enjoy VIP offers and your VIP prepaid card.' : 'Member since ${fmtDate(s.vipSince)}')
                    : 'VIP offers, a VIP prepaid card and more.',
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
      if (!s.isVip && s.kycStatus.isNotEmpty && !s.kycVerified) ...[
        const SizedBox(height: 14),
        const _VipKycReminder(),
      ],
      if (s.isVip) ...[
        const SizedBox(height: 14),
        _vipDone(context, s),
      ] else if (s.plans.isEmpty) ...[
        const EmptyState(icon: Icons.workspace_premium_rounded, title: 'No VIP plan is open right now', subtitle: 'Please check again later.'),
      ] else ...[
        if (pendingActive) ...[
          const SizedBox(height: 14),
          Material(
            color: p.primarySoft,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              leading: const Icon(Icons.qr_code_2_rounded, color: X9Colors.primary),
              title: const Text('Payment waiting', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Continue your VIP Club payment'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _resume(pending!),
            ),
          ),
        ],
        const SectionTitle('Choose your card'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'COMMON', label: Text('Common'), icon: Icon(Icons.credit_card_rounded)),
              ButtonSegment(value: 'VIP', label: Text('VIP'), icon: Icon(Icons.workspace_premium_rounded)),
            ],
            selected: {_tier},
            onSelectionChanged: (v) => setState(() {
              _tier = v.first;
              final of = s.plans.where((p) => p.tier == _tier);
              if (of.isNotEmpty) _planId = of.first.id;
            }),
          ),
        ),
        for (final plan in s.plans.where((p) => p.tier == _tier)) _planCard(context, plan),
        if (!s.plans.any((p) => p.tier == _tier)) const EmptyState(icon: Icons.credit_card_off_rounded, title: 'This card is not open right now', subtitle: 'Try the other card.'),
        const SizedBox(height: 8),
        _referralBox(context, s),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy || _plan == null ? null : _join,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Icon(Icons.workspace_premium_rounded),
          label: Text(_plan == null ? 'Get card' : '${_plan!.isVipTier ? 'Join VIP Club' : 'Get Common card'} - ${money(_plan!.price, compact: true)}'),
        ),
        const SizedBox(height: 10),
        Text(
          'You pay with any UPI app by scanning a QR. Your VIP card is ready to collect after payment.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4),
        ),
      ],
    ]);
  }

  /// Optional sales-team referral code (never required to buy a card).
  Widget _referralBox(BuildContext context, VipStatus s) {
    final p = context.x9;
    if (s.referralCode.isNotEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.verified_rounded, color: X9Colors.success),
        title: Text('Referred by ${s.referralName.isEmpty ? s.referralCode : s.referralName}'),
        subtitle: Text('Code ${s.referralCode}'),
      );
    }
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _refCtl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: 'Sales team referral code (optional)', filled: true, fillColor: p.surface),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(onPressed: _refBusy ? null : _saveReferral, child: const Text('Apply')),
    ]);
  }

  Widget _vipDone(BuildContext context, VipStatus s) {
    final pur = s.purchase;
    final paid = pur != null && vipIsPaid(vipPurchaseStatus(pur));
    return Card(
      child: ListTile(
        leading: const Icon(Icons.credit_card_rounded, color: X9Colors.primary),
        title: const Text('VIP card', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(paid ? vipFulfilmentLabel(str(pur?['fulfilment_status'])) : 'Your VIP card is managed in Prepaid card'),
      ),
    );
  }

  Widget _planCard(BuildContext context, VipPlan plan) {
    final p = context.x9;
    final selected = plan.id == _planId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _planId = plan.id),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? X9Colors.primary : p.border, width: selected ? 2 : 1.2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? X9Colors.primary : p.textMuted),
              const SizedBox(width: 10),
              Expanded(child: Text(plan.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              Text(money(plan.price, compact: true), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: X9Colors.primary, fontFeatures: X9Text.tabular)),
            ]),
            if (plan.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(plan.description, style: TextStyle(color: p.textSecondary, height: 1.35)),
            ],
            if (plan.benefits.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final b in plan.benefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: X9Colors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b, style: const TextStyle(height: 1.3))),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// KYC reminder inside the VIP page.
class _VipKycReminder extends StatelessWidget {
  const _VipKycReminder();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: context.x9.primarySoft, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.verified_user_rounded, color: X9Colors.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Complete KYC to join the VIP Club.', style: TextStyle(fontWeight: FontWeight.w600))),
          TextButton(onPressed: () => openKyc(context), child: const Text('KYC')),
        ]),
      );
}

/// Dynamic QR for a VIP purchase, "Pay with UPI app", and a 3-second poll of
/// `GET /app/vip/purchases/{purchase_id}` until PAID or expired.
class VipPayScreen extends StatefulWidget {
  const VipPayScreen({super.key, required this.purchase});
  final Map<String, dynamic> purchase;

  @override
  State<VipPayScreen> createState() => _VipPayScreenState();
}

class _VipPayScreenState extends State<VipPayScreen> {
  late Map<String, dynamic> _p = Map<String, dynamic>.from(widget.purchase);
  Timer? _timer;
  bool _checking = false;
  bool _opened = false;

  String get _id => str(_p['purchase_id'], str(_p['id']));
  String get _status => vipPurchaseStatus(_p);
  bool get _paid => vipIsPaid(_status);
  bool get _dead => vipIsDead(_status);

  @override
  void initState() {
    super.initState();
    if (!_paid && !_dead) _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _id.isEmpty || !mounted) return;
    _checking = true;
    try {
      final r = asMap(await Api.instance.get('/app/vip/purchases/$_id'));
      if (!mounted) return;
      final merged = <String, dynamic>{..._p, ...r};
      setState(() => _p = merged);
      final st = vipPurchaseStatus(merged);
      if (vipIsPaid(st)) {
        _timer?.cancel();
        await saveProfileUser({'is_vip': true});
        AppState.instance.refreshFeed();
      } else if (vipIsDead(st)) {
        _timer?.cancel();
      } else if (vipExpired(str(merged['expires_at']))) {
        _timer?.cancel();
        setState(() => _p = {...merged, 'status': 'EXPIRED'});
      }
    } catch (_) {
      // keep polling; a network blip must not stop the payment check
    } finally {
      _checking = false;
    }
  }

  Future<void> _openUpi() async {
    final ok = await openExternal(context, str(_p['upi_intent']), failMessage: 'No UPI app found. Scan the QR from another phone instead.');
    if (ok && mounted) setState(() => _opened = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('X9 VIP Club')),
      body: SafeArea(child: _paid ? _success(context) : _dead ? _expired(context) : _waiting(context)),
    );
  }

  Widget _waiting(BuildContext context) {
    final p = context.x9;
    final plan = asMap(_p['plan']);
    final planName = plan.isNotEmpty ? str(plan['name']) : str(_p['plan']);
    final exp = _p['expires_at'];
    final intent = str(_p['upi_intent']);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(money(asInt(_p['amount'])), textAlign: TextAlign.center, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -1)),
      const SizedBox(height: 4),
      Text(planName.isEmpty ? 'X9 VIP Club' : 'X9 VIP Club - $planName', textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
      const SizedBox(height: 20),
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: p.shadow, blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: UpiQrImage(qr: str(_p['qr']), intent: intent),
        ),
      ),
      if (str(_p['payee_name']).isNotEmpty || str(_p['payee_vpa']).isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('${str(_p['payee_name'])}  ${str(_p['payee_vpa'])}'.trim(), textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
      ],
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text(_opened ? 'Waiting for your UPI app to confirm...' : 'Waiting for payment...', style: TextStyle(color: p.textSecondary)),
      ]),
      if (exp != null) ...[
        const SizedBox(height: 4),
        Text('Valid until ${fmtDate(exp)}', textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary, fontSize: 12)),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: intent.isEmpty ? null : _openUpi, icon: const Icon(Icons.open_in_new_rounded), label: const Text('Pay with UPI app')),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: _check, icon: const Icon(Icons.refresh_rounded), label: const Text('I have paid - check status')),
      const SizedBox(height: 16),
      Text(
        'Scan the QR with any UPI app (GPay, PhonePe, Paytm, BHIM...). VIP is switched on as soon as the bank confirms the payment.',
        textAlign: TextAlign.center,
        style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4),
      ),
    ]);
  }

  Widget _expired(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.timer_off_rounded, size: 56, color: X9Colors.error),
          const SizedBox(height: 14),
          Text('Payment ${_status == 'EXPIRED' ? 'expired' : _status.toLowerCase()}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'If money left your account, it is returned by your bank. You can start the VIP Club payment again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.x9.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 22),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
        ]),
      );

  Widget _success(BuildContext context) {
    final p = context.x9;
    final fulfilment = str(_p['fulfilment_status'], 'CARD_PENDING').toUpperCase();
    final utr = str(_p['utr']);
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 16),
      const Icon(Icons.workspace_premium_rounded, size: 72, color: X9Colors.success),
      const SizedBox(height: 14),
      Text('Welcome to X9 VIP Club', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text('Payment received. You are a VIP member now.', textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
      const SizedBox(height: 22),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.credit_card_rounded, color: X9Colors.primary),
            title: Text(vipFulfilmentLabel(fulfilment), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Card status: ${fulfilment.replaceAll('_', ' ').toLowerCase()}'),
          ),
          if (utr.isNotEmpty) ListTile(dense: true, title: const Text('UTR'), trailing: Text(utr, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (str(_p['paid_at']).isNotEmpty) ListTile(dense: true, title: const Text('Paid'), trailing: Text(fmtDate(_p['paid_at']))),
        ]),
      ),
      const SizedBox(height: 22),
      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
    ]);
  }
}
