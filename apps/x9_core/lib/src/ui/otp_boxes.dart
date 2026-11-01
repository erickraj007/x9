import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// OTP boxes backed by one hidden text field (paste and autofill work). Self-contained copy for the shared
/// sign-up flow; the apps keep their own `OtpBoxes` for the existing sign-in screens.
class X9OtpBoxes extends StatefulWidget {
  const X9OtpBoxes({super.key, required this.length, required this.controller, this.onCompleted, this.autofocus = false});
  final int length;
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;

  @override
  State<X9OtpBoxes> createState() => _X9OtpBoxesState();
}

class _X9OtpBoxesState extends State<X9OtpBoxes> {
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
                margin: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(maxWidth: 52),
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? X9Colors.primary : (filled ? X9Colors.primary.withValues(alpha: 0.4) : p.border),
                    width: active ? 2 : 1.4,
                  ),
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
