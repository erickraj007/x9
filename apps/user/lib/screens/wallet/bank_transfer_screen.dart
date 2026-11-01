import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/amount_entry.dart';
import 'wallet_actions.dart';

/// X9 wallet → own bank account (verified beneficiary) or a UPI ID (USR > PAYOUT).
class BankTransferScreen extends StatefulWidget {
  const BankTransferScreen({super.key});

  @override
  State<BankTransferScreen> createState() => _BankTransferScreenState();
}

class _BankTransferScreenState extends State<BankTransferScreen> {
  String _mode = 'BANK';
  List<Map<String, dynamic>>? _bens;
  Object? _error;
  int? _selected;
  final _vpa = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _vpa.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = asList(await Api.instance.get('/app/beneficiaries')).map(asMap).toList();
      if (!mounted) return;
      setState(() {
        _bens = r;
        _error = null;
        final usable = r.where(_usable).toList();
        if (_selected == null && usable.isNotEmpty) {
          final primary = usable.where((b) => asBool(b['is_primary'])).toList();
          _selected = asInt((primary.isNotEmpty ? primary.first : usable.first)['id']);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool _usable(Map<String, dynamic> b) => str(b['status']).toUpperCase() == 'VERIFIED';

  void _continue() {
    if (_mode == 'BANK') {
      final b = (_bens ?? const []).where((x) => asInt(x['id']) == _selected).toList();
      if (b.isEmpty) {
        showError(context, 'Choose a verified bank account.');
        return;
      }
      final ben = b.first;
      final label = '${str(ben['bank_name'], 'Bank')} ••${str(ben['account_last4'])}';
      go(
        context,
        AmountEntryScreen(
          title: 'Transfer to bank',
          recipient: RecipientHeader(icon: Icons.account_balance_rounded, title: str(ben['account_holder'], 'Bank account'), subtitle: '$label · ${str(ben['ifsc'])}'),
          available: AppState.instance.knownClubBalance,
          actionLabel: 'Review',
          onSubmit: (ctx, paise) => walletPay(
            ctx,
            amount: paise,
            body: {'to_type': 'PAYOUT', 'payout_mode': 'BANK'},
            title: 'Transfer to bank',
            resultTitle: 'Bank transfer requested',
            rows: [MapEntry('To', label), MapEntry('IFSC', str(ben['ifsc']))],
          ),
        ),
      );
    } else {
      final v = _vpa.text.trim();
      if (!RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(v)) {
        showError(context, 'Enter a valid UPI ID, e.g. name@okaxis');
        return;
      }
      go(
        context,
        AmountEntryScreen(
          title: 'Transfer to UPI ID',
          recipient: RecipientHeader(icon: Icons.alternate_email_rounded, title: v, subtitle: 'UPI transfer'),
          available: AppState.instance.knownClubBalance,
          actionLabel: 'Review',
          onSubmit: (ctx, paise) => walletPay(
            ctx,
            amount: paise,
            body: {'to_type': 'PAYOUT', 'payout_mode': 'UPI', 'upi_vpa': v},
            title: 'Transfer to UPI ID',
            resultTitle: 'UPI transfer requested',
            rows: [MapEntry('To UPI ID', v)],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('To bank / UPI')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'BANK', icon: Icon(Icons.account_balance_rounded), label: Text('Bank account')),
              ButtonSegment(value: 'UPI', icon: Icon(Icons.alternate_email_rounded), label: Text('UPI ID')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 18),
          if (_mode == 'BANK') ..._bankSection() else ..._upiSection(),
          const SizedBox(height: 24),
          FilledButton(onPressed: _continue, child: const Text('Continue')),
          const SizedBox(height: 12),
          Text(
            'Bank transfers are paid out after a quick check by X9 finance. If a transfer fails, the money comes back to your X9 wallet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5),
          ),
        ]),
      ),
    );
  }

  List<Widget> _upiSection() => [
        TextField(
          controller: _vpa,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'UPI ID', hintText: 'name@bank', prefixIcon: Icon(Icons.alternate_email_rounded)),
        ),
      ];

  List<Widget> _bankSection() {
    if (_error != null && _bens == null) return [ErrorRetry(message: friendlyError(_error!), onRetry: _load)];
    if (_bens == null) return const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))];
    final list = _bens!;
    return [
      if (list.isEmpty)
        const EmptyState(icon: Icons.account_balance_outlined, title: 'No bank account yet', subtitle: 'Add your own bank account. It is verified once by X9.'),
      for (final b in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: RadioListTile<int>(
              value: asInt(b['id']),
              groupValue: _selected,
              onChanged: _usable(b) ? (v) => setState(() => _selected = v) : null,
              title: Text(str(b['account_holder'], 'Account'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${str(b['bank_name'], 'Bank')} ••${str(b['account_last4'])} · ${str(b['ifsc'])}'),
              secondary: StatusChip(str(b['status'])),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () async {
          final added = await go<bool>(context, const AddBankAccountScreen());
          if (added == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add bank account'),
      ),
    ];
  }
}

/// POST /app/beneficiaries {account_holder, account_number, ifsc, bank_name?}
class AddBankAccountScreen extends StatefulWidget {
  const AddBankAccountScreen({super.key});

  @override
  State<AddBankAccountScreen> createState() => _AddBankAccountScreenState();
}

class _AddBankAccountScreenState extends State<AddBankAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _holder = TextEditingController(text: str(SessionStore.instance.user?['name']));
  final _acc = TextEditingController();
  final _acc2 = TextEditingController();
  final _ifsc = TextEditingController();
  final _bank = TextEditingController();

  @override
  void dispose() {
    for (final c in [_holder, _acc, _acc2, _ifsc, _bank]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    try {
      await Api.instance.post('/app/beneficiaries', {
        'account_holder': _holder.text.trim(),
        'account_number': _acc.text.trim(),
        'ifsc': _ifsc.text.trim().toUpperCase(),
        if (_bank.text.trim().isNotEmpty) 'bank_name': _bank.text.trim(),
      });
    } catch (e) {
      // KYC_REQUIRED opens the KYC screen (v6.13); any other error is shown as a message.
      if (mounted) showFriendlyError(context, e);
      return;
    }
    if (!mounted) return;
    showOk(context, 'Bank account added. It will be verified shortly.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add bank account')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _holder,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Account holder name'),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the name on the account' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _acc,
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Account number'),
            validator: (v) => RegExp(r'^\d{9,18}$').hasMatch((v ?? '').trim()) ? null : '9 to 18 digits',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _acc2,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Re-enter account number'),
            validator: (v) => (v ?? '').trim() == _acc.text.trim() ? null : 'Account numbers do not match',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _ifsc,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'IFSC', hintText: 'e.g. SBIN0001234'),
            validator: (v) => RegExp(r'^[A-Za-z]{4}0[A-Za-z0-9]{6}$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid 11-character IFSC',
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _bank, decoration: const InputDecoration(labelText: 'Bank name (optional)')),
          const SizedBox(height: 24),
          BusyButton(label: 'Save bank account', icon: Icons.check_rounded, onPressed: _save),
          const SizedBox(height: 12),
          Text(
            'Only your own account can be added. The account number is stored encrypted.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5),
          ),
        ]),
      ),
    );
  }
}
