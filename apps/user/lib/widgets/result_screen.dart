import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import 'bits.dart';

class ResultAction {
  const ResultAction(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final void Function(BuildContext context) onPressed;
}

/// Payment / transfer result: animated tick (success), clock (pending/requested) or cross (failed).
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.status,
    required this.title,
    this.amount,
    this.message,
    this.reference,
    this.details = const [],
    this.actions = const [],
    this.onShown,
  });

  /// SUCCESS | PENDING | REQUESTED | FAILED
  final String status;
  final String title;
  final int? amount;
  final String? message;
  final String? reference;
  final List<MapEntry<String, String>> details;
  final List<ResultAction> actions;

  /// Runs once, shortly after the screen appears (e.g. ask for a rating after a successful payment).
  final void Function(BuildContext context)? onShown;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    if (_success) {
      HapticFeedback.mediumImpact();
    } else if (_failed) {
      HapticFeedback.heavyImpact();
    }
    final cb = widget.onShown;
    if (cb != null) {
      Future.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) cb(context);
      });
    }
  }

  bool get _success => widget.status.toUpperCase() == 'SUCCESS';
  bool get _failed => widget.status.toUpperCase() == 'FAILED';

  @override
  Widget build(BuildContext context) {
    final color = _success ? X9Colors.success : (_failed ? X9Colors.error : X9Colors.primary);
    final icon = _success ? Icons.check_rounded : (_failed ? Icons.close_rounded : Icons.schedule_rounded);
    final headline = _success ? 'Successful' : (_failed ? 'Failed' : 'In progress');
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.16), Theme.of(context).scaffoldBackgroundColor],
            begin: Alignment.topCenter,
            end: Alignment.center,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(children: [
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (context, v, child) => Transform.scale(scale: v, child: child),
                    child: Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 4)],
                      ),
                      child: Icon(icon, color: Colors.white, size: 64),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(headline.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w600, letterSpacing: 1.4, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(widget.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  if (widget.amount != null) ...[
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: widget.amount!.toDouble()),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(money(v.round()), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w600, letterSpacing: -1)),
                    ),
                  ],
                  if (widget.message != null && widget.message!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(widget.message!, textAlign: TextAlign.center, style: TextStyle(color: _failed ? context.x9.statusText(X9Colors.error) : context.x9.textSecondary, height: 1.4)),
                  ],
                  if (widget.details.isNotEmpty || (widget.reference ?? '').isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Column(children: [
                          for (final d in widget.details) KvRow(d.key, d.value),
                          if ((widget.reference ?? '').isNotEmpty)
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: widget.reference!));
                                showOk(context, 'Reference copied');
                              },
                              child: KvRow('Reference', widget.reference!),
                            ),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(children: [
                for (final a in widget.actions) ...[
                  OutlinedButton.icon(onPressed: () => a.onPressed(context), icon: Icon(a.icon), label: Text(a.label)),
                  const SizedBox(height: 10),
                ],
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
