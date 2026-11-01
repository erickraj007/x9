import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/skeleton.dart';

/// Card usage limits (GET/PUT /app/cards/{id}/limits; PUT is signed with amount 0). Amounts in paise.
class CardLimitsScreen extends StatefulWidget {
  const CardLimitsScreen({super.key, required this.cardId});
  final int cardId;

  @override
  State<CardLimitsScreen> createState() => _CardLimitsScreenState();
}

class _CardLimitsScreenState extends State<CardLimitsScreen> {
  final _daily = TextEditingController();
  final _perTxn = TextEditingController();
  final _monthly = TextEditingController();
  bool _atm = true;
  bool _pos = true;
  bool _ecom = true;
  bool _contactless = true;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _daily.dispose();
    _perTxn.dispose();
    _monthly.dispose();
    super.dispose();
  }

  String _rupees(dynamic paise) {
    if (paise == null) return '';
    final p = asInt(paise);
    return p % 100 == 0 ? '${p ~/ 100}' : (p / 100).toStringAsFixed(2);
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Api.instance.get('/app/cards/${widget.cardId}/limits'));
      if (!mounted) return;
      setState(() {
        _daily.text = _rupees(r['daily_limit']);
        _perTxn.text = _rupees(r['per_txn_limit']);
        _monthly.text = _rupees(r['monthly_limit']);
        _atm = r['atm_enabled'] == null ? true : asBool(r['atm_enabled']);
        _pos = r['pos_enabled'] == null ? true : asBool(r['pos_enabled']);
        _ecom = r['ecom_enabled'] == null ? true : asBool(r['ecom_enabled']);
        _contactless = r['contactless_enabled'] == null ? true : asBool(r['contactless_enabled']);
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    final daily = toPaise(_daily.text);
    final per = toPaise(_perTxn.text);
    final monthly = toPaise(_monthly.text);
    if (daily == null || per == null || monthly == null) throw Exception('Enter all three limits in rupees.');
    if (per > daily) throw Exception('Per-transaction limit cannot be more than the daily limit.');
    if (daily > monthly) throw Exception('Daily limit cannot be more than the monthly limit.');
    final ok = await AppLock.instance.confirm(context, reason: 'Save card limits');
    if (!ok || !mounted) return;
    await Api.instance.money(
      'PUT',
      '/app/cards/${widget.cardId}/limits',
      {
        'daily_limit': daily,
        'per_txn_limit': per,
        'monthly_limit': monthly,
        'atm_enabled': _atm,
        'pos_enabled': _pos,
        'ecom_enabled': _ecom,
        'contactless_enabled': _contactless,
      },
      amount: 0,
    );
    if (!mounted) return;
    showOk(context, 'Card limits saved');
    Navigator.pop(context);
  }

  Widget _field(String label, String hint, TextEditingController c, List<int> quick) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(labelText: label, helperText: hint, prefixText: '₹ '),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final q in quick)
              ActionChip(
                label: Text(money(q * 100, compact: true)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => c.text = '$q'),
              ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usage limits')),
      body: !_loaded
          ? (_error != null ? ErrorRetry(message: friendlyError(_error!), onRetry: _load) : const SkeletonList(count: 4))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Spending limits', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 14),
                      _field('Per transaction', 'Largest single payment', _perTxn, const [2000, 5000, 10000]),
                      _field('Daily', 'Total per day', _daily, const [10000, 25000, 50000]),
                      _field('Monthly', 'Total per month', _monthly, const [50000, 100000, 200000]),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      value: _atm,
                      onChanged: (v) => setState(() => _atm = v),
                      secondary: const Icon(Icons.local_atm_rounded),
                      title: const Text('ATM withdrawals'),
                    ),
                    SwitchListTile(
                      value: _pos,
                      onChanged: (v) => setState(() => _pos = v),
                      secondary: const Icon(Icons.point_of_sale_rounded),
                      title: const Text('Shops (card machine)'),
                    ),
                    SwitchListTile(
                      value: _ecom,
                      onChanged: (v) => setState(() => _ecom = v),
                      secondary: const Icon(Icons.shopping_cart_rounded),
                      title: const Text('Online payments'),
                    ),
                    SwitchListTile(
                      value: _contactless,
                      onChanged: (v) => setState(() => _contactless = v),
                      secondary: const Icon(Icons.contactless_rounded),
                      title: const Text('Contactless (tap to pay)'),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                BusyButton(label: 'Save limits', icon: Icons.lock_rounded, onPressed: _save),
              ]),
            ),
    );
  }
}
