import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:x9_core/x9_core.dart';

import '../util/helpers.dart';
import 'bits.dart';

/// Full-screen amount entry with a large figure and an on-screen keypad (no system keyboard).
class AmountEntryScreen extends StatefulWidget {
  const AmountEntryScreen({
    super.key,
    required this.title,
    required this.onSubmit,
    this.recipient,
    this.available,
    this.availableLabel = 'X9 wallet balance',
    this.minPaise = 100,
    this.maxPaise,
    this.actionLabel = 'Continue',
    this.initialPaise,
  });

  final String title;

  /// Who/where the money goes (shown above the amount).
  final Widget? recipient;
  final int? available;
  final String availableLabel;
  final int minPaise;
  final int? maxPaise;
  final String actionLabel;
  final int? initialPaise;

  /// Runs with this screen's context; usually shows the review sheet, unlocks and calls the API.
  final Future<void> Function(BuildContext context, int paise) onSubmit;

  @override
  State<AmountEntryScreen> createState() => _AmountEntryScreenState();
}

class _AmountEntryScreenState extends State<AmountEntryScreen> {
  String _text = '';
  bool _busy = false;
  static final NumberFormat _grp = NumberFormat.decimalPattern('en_IN');

  @override
  void initState() {
    super.initState();
    final p = widget.initialPaise;
    if (p != null && p > 0) {
      _text = p % 100 == 0 ? '${p ~/ 100}' : (p / 100).toStringAsFixed(2);
    }
  }

  int? get _paise => toPaise(_text);

  String? get _problem {
    final p = _paise;
    if (p == null) return null;
    if (p < widget.minPaise) return 'Minimum ${money(widget.minPaise, compact: true)}';
    if (widget.maxPaise != null && p > widget.maxPaise!) return 'Maximum ${money(widget.maxPaise, compact: true)}';
    if (widget.available != null && p > widget.available!) return 'More than your available balance';
    return null;
  }

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '<') {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
        return;
      }
      if (k == '.') {
        if (_text.contains('.')) return;
        _text = _text.isEmpty ? '0.' : '$_text.';
        return;
      }
      final dot = _text.indexOf('.');
      if (dot >= 0 && _text.length - dot > 2) return; // max 2 decimals
      if (dot < 0 && _text.replaceAll('.', '').length >= 7) return; // ₹99,99,999 max
      if (_text == '0') {
        _text = k;
      } else {
        _text += k;
      }
    });
  }

  void _add(int rupees) {
    final cur = _paise ?? 0;
    final next = cur + rupees * 100;
    setState(() => _text = next % 100 == 0 ? '${next ~/ 100}' : (next / 100).toStringAsFixed(2));
  }

  String get _display {
    if (_text.isEmpty) return '0';
    final parts = _text.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    final w = _grp.format(whole);
    return parts.length > 1 ? '$w.${parts[1]}' : w;
  }

  Future<void> _submit() async {
    final p = _paise;
    if (p == null || _problem != null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(context, p);
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final ok = _paise != null && problem == null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(children: [
          if (widget.recipient != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: widget.recipient!),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('₹', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: _text.isEmpty ? context.x9.textSecondary : null)),
                        ),
                        const SizedBox(width: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 120),
                          child: Text(
                            _display,
                            key: ValueKey(_display),
                            style: TextStyle(fontSize: 54, fontWeight: FontWeight.w600, letterSpacing: -1.5, fontFeatures: X9Text.tabular, color: _text.isEmpty ? context.x9.textSecondary : null),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 20,
                    child: Text(
                      problem ?? (widget.available != null ? '${widget.availableLabel}: ${money(widget.available)}' : ''),
                      style: TextStyle(color: problem != null ? context.x9.statusText(X9Colors.error) : context.x9.textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, children: [
                    for (final r in const [100, 500, 1000, 2000])
                      ActionChip(label: Text('+ ₹$r'), onPressed: () => _add(r), shape: const StadiumBorder()),
                  ]),
                ]),
              ),
            ),
          ),
          _Keypad(onKey: _key),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: FilledButton(
              onPressed: ok && !_busy ? _submit : null,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(widget.actionLabel),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});
  final void Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    Widget k(String v) => Expanded(
          child: InkWell(
            onTap: () => onKey(v),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 56,
              child: Center(
                child: v == '<'
                    ? const Icon(Icons.backspace_outlined)
                    : Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['.', '0', '<'],
        ])
          Row(children: [for (final v in row) k(v)]),
      ]),
    );
  }
}

/// Recipient strip shown on the amount screen.
class RecipientHeader extends StatelessWidget {
  const RecipientHeader({super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
      );
}

/// Review bottom sheet before any money movement. Returns true when the person taps confirm.
Future<bool> showReviewSheet(
  BuildContext context, {
  required String title,
  required int amount,
  List<MapEntry<String, String>> rows = const [],
  String confirmLabel = 'Confirm',
  String? warning,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(money(amount), textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: context.x9.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [for (final r in rows) KvRow(r.key, r.value)]),
          ),
          if (warning != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: X9Colors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(warning, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5))),
            ]),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.lock_rounded, size: 18),
            label: Text(confirmLabel),
          ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        ]),
      ),
    ),
  );
  if (ok == true) Api.instance.markConfirmed(); // the review sheet is the confirmation: no second pop-up
  return ok == true;
}
