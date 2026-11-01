import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/amount_entry.dart';
import '../../widgets/result_screen.dart';
import '../../widgets/upi_qr.dart';

/// Largest single wallet load: Rs 99,000 (server limit X9_USER_MAX_LOAD_PAISE).
const int walletLoadMaxPaise = 9900000;

/// `GET /app/wallet/loads/{load_id}` - status of one wallet load (instant credit confirmation).
Future<Map<String, dynamic>> getLoad(String loadId) async {
  final r = asMap(await Api.instance.get('/app/wallet/loads/$loadId'));
  final inner = asMap(r['load']);
  return inner.isNotEmpty ? inner : r;
}

/// Add money: amount → POST /app/wallet/load → pay the UPI collection request (QR or UPI app).
class LoadWalletScreen extends StatelessWidget {
  const LoadWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AmountEntryScreen(
      title: 'Add money to X9 wallet',
      recipient: const RecipientHeader(icon: Icons.account_balance_wallet_rounded, title: 'X9 Club wallet', subtitle: 'Pay with any UPI app'),
      actionLabel: 'Proceed to pay',
      maxPaise: walletLoadMaxPaise,
      onSubmit: (ctx, paise) async {
        final unlocked = await AppLock.instance.confirm(ctx, reason: 'Add ${money(paise)} to X9 wallet');
        if (!unlocked || !ctx.mounted) return;
        final r = asMap(await Api.instance.money('POST', '/app/wallet/load', {'amount': paise}, amount: paise));
        if (!ctx.mounted) return;
        Navigator.of(ctx).pushReplacement(MaterialPageRoute<void>(builder: (_) => UpiLoadScreen(load: r)));
      },
    );
  }
}

/// Shows the UPI request as a QR and an "Open UPI app" button; polls until the load is credited.
class UpiLoadScreen extends StatefulWidget {
  const UpiLoadScreen({super.key, required this.load});
  final Map<String, dynamic> load;

  @override
  State<UpiLoadScreen> createState() => _UpiLoadScreenState();
}

class _UpiLoadScreenState extends State<UpiLoadScreen> {
  Timer? _poll;
  String _status = 'PENDING';
  bool _opened = false;
  bool _checking = false;

  String get _intent => str(widget.load['upi_intent']);
  int get _amount => asInt(widget.load['amount']);
  String get _vpa => Uri.tryParse(_intent)?.queryParameters['pa'] ?? '';

  @override
  void initState() {
    super.initState();
    _status = str(widget.load['status'], 'PENDING').toUpperCase();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  static const _done = {'SUCCESS', 'PAID', 'CREDITED', 'COMPLETED'};
  static const _failed = {'FAILED', 'EXPIRED', 'REJECTED', 'CANCELLED'};

  /// One status check: the load endpoint first; the wallet's load list when that endpoint is not available.
  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final id = str(widget.load['load_id'], str(widget.load['id']));
      Map<String, dynamic>? m;
      if (id.isNotEmpty) {
        try {
          m = await getLoad(id);
        } on ApiException catch (e) {
          if (e.status != 404 && e.status != 405) rethrow;
        }
      }
      m ??= await _findInWallet(id);
      if (m == null || !mounted) return;
      _apply(m, id);
    } catch (_) {
      // keep polling
    } finally {
      _checking = false;
    }
  }

  Future<Map<String, dynamic>?> _findInWallet(String id) async {
    final r = asMap(await Api.instance.get('/app/wallet'));
    for (final l in asList(r['loads'])) {
      final m = asMap(l);
      if (str(m['load_id']) == id || (id.isEmpty && asInt(m['id']) == asInt(widget.load['id']))) return m;
    }
    return null;
  }

  void _apply(Map<String, dynamic> m, String id) {
    final s = str(m['status']).toUpperCase();
    if (s.isEmpty) return;
    if (s != _status) setState(() => _status = s);
    if (!_done.contains(s) && !_failed.contains(s)) return;
    if (s == 'EXPIRED' && (_claimed.isNotEmpty || str(m['claimed_utr']).isNotEmpty)) return; // v6.18.3: waiting for the bank to confirm the UTR
    _poll?.cancel();
    AppState.instance.refreshBalances();
    final ok = _done.contains(s);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ResultScreen(
        status: ok ? 'SUCCESS' : 'FAILED',
        title: ok ? 'Money added to X9 wallet' : 'Wallet load ${s.toLowerCase()}',
        amount: _amount,
        message: ok ? null : str(m['failure_reason'], 'If money left your bank, it is returned by your bank.'),
        reference: str(m['utr'], id),
      ),
    ));
  }

  /// v6.18.3: paid but not credited yet - send the UTR / UPI reference from the UPI app. The wallet is credited when the
  /// bank alert with the same UTR arrives (or X9 confirms it against the bank statement).
  String _claimed = '';

  Future<void> _enterUtr() async {
    final c = TextEditingController();
    final utr = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Enter UTR'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Open this payment in your UPI app (PhonePe, Google Pay, Paytm...) and copy the UTR / UPI reference number (usually 12 digits) for ${money(_amount)}.',
              style: TextStyle(color: context.x9.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, maxLength: 22, decoration: const InputDecoration(labelText: 'UTR / UPI reference', hintText: 'e.g. 931752280301')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, c.text.replaceAll(RegExp(r'\s'), '')), child: const Text('Send')),
        ],
      ),
    );
    if (utr == null || utr.isEmpty || !mounted) return;
    final id = str(widget.load['load_id'], str(widget.load['id']));
    try {
      final r = asMap(await withProgress(context, () => Api.instance.post('/app/wallet/loads/$id/utr', {'utr': utr})));
      if (!mounted) return;
      setState(() => _claimed = str(r['claimed_utr'], utr));
      showOk(context, str(r['message'], 'UTR received'));
      _apply(r, id);
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  Future<void> _openUpi() async {
    final ok = await openExternal(context, _intent, failMessage: 'No UPI app found. Scan the QR from another phone instead.');
    if (ok && mounted) setState(() => _opened = true);
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.load['expires_at'];
    return Scaffold(
      appBar: AppBar(title: const Text('Pay with UPI')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(money(_amount), textAlign: TextAlign.center, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -1)),
          const SizedBox(height: 4),
          Text('to your X9 Club wallet', textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary)),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: context.x9.shadow, blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: UpiQrImage(qr: str(widget.load['qr']), intent: _intent),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(_opened ? 'Waiting for your UPI app to confirm…' : 'Waiting for payment…', style: TextStyle(color: context.x9.textSecondary)),
          ]),
          if (exp != null) ...[
            const SizedBox(height: 4),
            Text('Request valid until ${fmtDate(exp)}', textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _intent.isEmpty ? null : _openUpi, icon: const Icon(Icons.open_in_new_rounded), label: const Text('Open UPI app')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _check, icon: const Icon(Icons.refresh_rounded), label: const Text('I have paid — check status')),
          const SizedBox(height: 6),
          // v6.18.4: if the UPI app does not open or refuses the link, pay to the UPI ID by hand (any UPI app > Pay to UPI ID)
          if (_vpa.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _vpa));
                if (mounted) showOk(context, 'UPI ID $_vpa copied. In your UPI app choose "Pay to UPI ID", pay ${money(_amount)}, then enter the UTR here.');
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text('UPI app not opening? Copy UPI ID $_vpa'),
            ),
          if (_claimed.isEmpty)
            TextButton.icon(onPressed: _enterUtr, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Paid but not credited? Enter UTR'))
          else
            Text('UTR $_claimed received. Your wallet is credited as soon as the bank confirms this payment.',
                textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 16),
          Text(
            'Pay from any UPI app (GPay, PhonePe, Paytm, BHIM…). Your wallet is credited as soon as the bank confirms the payment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ]),
      ),
    );
  }
}
