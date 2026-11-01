import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

/// OTP boxes backed by one hidden text field (paste and SMS autofill work).
class OtpBoxes extends StatefulWidget {
  const OtpBoxes({super.key, required this.length, required this.controller, this.onCompleted, this.autofocus = false});
  final int length;
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final p = context.x9;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (i) {
            final filled = i < text.length;
            final active = _focus.hasFocus && (i == text.length || (i == widget.length - 1 && text.length == widget.length));
            return Flexible(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                constraints: const BoxConstraints(maxWidth: 52),
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: active ? X9Colors.primary : (filled ? X9Colors.primary.withValues(alpha: 0.4) : p.border), width: active ? 2 : 1.4),
                ),
                child: Text(filled ? text[i] : '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              ),
            );
          }),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: widget.length,
              showCursor: false,
              enableInteractiveSelection: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(counterText: '', border: InputBorder.none, filled: false),
              onChanged: (v) {
                if (v.length == widget.length) widget.onCompleted?.call(v);
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// "Resend in 0:27" → "Resend OTP".
class ResendTimer extends StatefulWidget {
  const ResendTimer({super.key, required this.onResend, this.seconds = 30});
  final Future<void> Function() onResend;
  final int seconds;

  @override
  State<ResendTimer> createState() => _ResendTimerState();
}

class _ResendTimerState extends State<ResendTimer> {
  Timer? _t;
  int _left = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _t?.cancel();
    _left = widget.seconds;
    if (mounted) setState(() {});
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await widget.onResend();
      if (mounted) {
        showOk(context, 'OTP sent again');
        _start();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_left > 0) {
      return Text('Resend OTP in 0:${_left.toString().padLeft(2, '0')}', style: TextStyle(color: context.x9.textSecondary, fontWeight: FontWeight.w600));
    }
    return TextButton.icon(
      onPressed: _busy ? null : _resend,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Resend OTP'),
    );
  }
}
