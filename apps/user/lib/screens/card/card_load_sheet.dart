import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../kyc/kyc_entry.dart';
import '../wallet/load_wallet_screen.dart';
import 'card_load_success_screen.dart';

/// Add money to a prepaid card with a live fee preview (docs/PREPAID-CARD-V4.md section 8).
/// Returns true when the load went through (the success screen was shown).
Future<bool> showCardLoadSheet(BuildContext context, Map<String, dynamic> card) async {
  final r = await showModalBottomSheet<CardLoadResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CardLoadSheet(card: card),
  );
  if (r == null || !context.mounted) return false;
  AppState.instance.refreshBalances();
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CardLoadSuccessScreen(result: r, card: card)));
  return true;
}

class _CardLoadSheet extends StatefulWidget {
  const _CardLoadSheet({required this.card});
  final Map<String, dynamic> card;

  @override
  State<_CardLoadSheet> createState() => _CardLoadSheetState();
}

class _CardLoadSheetState extends State<_CardLoadSheet> {
  final TextEditingController _amount = TextEditingController();
  Timer? _debounce;
  FeePreview? _preview;
  bool _previewing = false;
  Object? _previewError;
  bool _paying = false;
  String? _payError;
  int _seq = 0;
  String? _key;
  int _keyAmount = 0;

  static const _quick = [50000, 100000, 200000, 500000];

  int get _cardId => asInt(widget.card['id']);
  int? get _paise => toPaise(_amount.text);

  @override
  void dispose() {
    _debounce?.cancel();
    _amount.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _payError = null;
    final p = _paise;
    if (p == null || p < 100) {
      setState(() {
        _preview = null;
        _previewError = null;
        _previewing = false;
      });
      return;
    }
    setState(() => _previewing = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetch(p));
  }

  Future<void> _fetch(int paise) async {
    final seq = ++_seq;
    try {
      final r = await CardApi.feePreview(_cardId, paise);
      if (!mounted || seq != _seq) return;
      setState(() {
        _preview = r;
        _previewError = null;
        _previewing = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _previewError = e;
        _previewing = false;
      });
    }
  }

  void _setQuick(int paise) {
    _amount.text = paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    _changed(_amount.text);
  }

  /// The preview matches what is typed (a stale answer must not be paid).
  bool get _previewFresh {
    final p = _paise;
    final v = _preview;
    return p != null && v != null && v.amount == p && !_previewing;
  }

  /// v6.2: pay straight from a UPI app on this phone; the amount (plus card fee) lands on the card.
  Future<void> _payUpi() async {
    final p = _paise;
    if (p == null || p <= 0 || _paying) return;
    setState(() { _paying = true; _payError = null; });
    try {
      final r = asMap(await Api.instance.money('POST', '/app/cards/$_cardId/load-upi', {'amount': p}, amount: p));
      if (!mounted) return;
      setState(() => _paying = false);
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UpiLoadScreen(load: r)));
      AppState.instance.refreshBalances();
    } catch (e) {
      if (!mounted) return;
      setState(() { _paying = false; _payError = friendlyError(e); });
    }
  }

  Future<void> _pay() async {
    final v = _preview;
    final p = _paise;
    if (v == null || p == null || !_previewFresh || _paying) return;
    final ok = await AppLock.instance.confirm(context, reason: 'Add ${money(p)} to card');
    if (!ok || !mounted) return;
    if (_key == null || _keyAmount != p) {
      _key = SessionStore.newIdempotencyKey();
      _keyAmount = p;
    }
    setState(() {
      _paying = true;
      _payError = null;
    });
    try {
      final r = await CardApi.load(_cardId, p, idempotencyKey: _key);
      if (!mounted) return;
      if (r.status == 'FAILED') {
        setState(() {
          _paying = false;
          _payError = str(r.raw['failure_reason'], 'The load could not be completed. No money was taken.');
        });
        return;
      }
      Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _payError = friendlyError(e);
      });
      if (isKycRequired(e)) showKycGate(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.x9;
    final balance = AppState.instance.knownClubBalance;
    final v = _preview;
    final p = _paise;
    final short = _previewFresh && balance != null && v!.youPay > balance;
    final masked = str(widget.card['masked_number'], 'X9 prepaid card');
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Add money to card', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(masked, textAlign: TextAlign.center, style: TextStyle(color: pal.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            autofocus: true,
            enabled: !_paying,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), LengthLimitingTextInputFormatter(10)],
            onChanged: _changed,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Amount to load',
              prefixText: '₹ ',
              helperText: balance == null ? null : 'X9 wallet balance ${money(balance)}',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in _quick) ActionChip(label: Text(money(q, compact: true)), onPressed: _paying ? null : () => _setQuick(q)),
          ]),
          const SizedBox(height: 14),
          if (v != null && p != null)
            FeeBreakdown.forPreview(v, loading: _previewing || v.amount != p)
          else if (_previewing)
            const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))))
          else
            Text('Enter an amount of ₹1 or more to see the card fee and what you pay.', style: TextStyle(color: pal.textMuted, fontSize: 12.5)),
          if (_previewError != null) ...[
            const SizedBox(height: 8),
            Text(friendlyError(_previewError!), style: TextStyle(color: pal.statusText(X9Colors.error), fontSize: 13)),
          ],
          if (short) ...[
            const SizedBox(height: 8),
            Text('Your X9 wallet does not have enough for this load and its fee. Add money to your wallet first.', style: TextStyle(color: pal.statusText(X9Colors.error), fontSize: 13)),
          ],
          if (_payError != null) ...[
            const SizedBox(height: 8),
            Text(_payError!, style: TextStyle(color: pal.statusText(X9Colors.error), fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_previewFresh && !short && !_paying) ? _pay : null,
            icon: _paying
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.lock_rounded, size: 18),
            label: Text(v != null && _previewFresh ? 'Pay ${money(v.youPay)}' : 'Pay'),
          ),
          OutlinedButton.icon(
            onPressed: (!_paying && (_paise ?? 0) > 0) ? _payUpi : null,
            icon: const Icon(Icons.account_balance_rounded, size: 18),
            label: const Text('Pay with UPI app (bank account)'),
          ),
          TextButton(onPressed: _paying ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ]),
      ),
    );
  }
}
