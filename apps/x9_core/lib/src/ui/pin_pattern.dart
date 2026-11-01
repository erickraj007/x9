import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Numeric keypad with dots. Calls [onCompleted] when [length] digits are entered.
class PinPad extends StatefulWidget {
  const PinPad({super.key, this.length = 4, required this.onCompleted, this.error, this.onBiometric});
  final int length;
  final void Function(String pin) onCompleted;
  final String? error;
  final VoidCallback? onBiometric;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';

  void clear() => setState(() => _pin = '');

  void _tap(String d) {
    if (_pin.length >= widget.length) return;
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final p = _pin;
      Future.delayed(const Duration(milliseconds: 120), () {
        widget.onCompleted(p);
        if (mounted) setState(() => _pin = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => SizedBox(
          width: 76,
          height: 64,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(40),
            child: Center(child: child ?? Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.length, (i) {
          final filled = i < _pin.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? X9Colors.primary : Colors.transparent,
              border: Border.all(color: widget.error != null ? X9Colors.error : X9Colors.primary, width: 2),
            ),
          );
        }),
      ),
      SizedBox(
        height: 30,
        child: Center(child: Text(widget.error ?? '', style: const TextStyle(color: X9Colors.error, fontWeight: FontWeight.w600))),
      ),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d, onTap: () => _tap(d))]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        key('', onTap: widget.onBiometric, child: widget.onBiometric == null ? const SizedBox() : const Icon(Icons.fingerprint_rounded, size: 30, color: X9Colors.primary)),
        key('0', onTap: () => _tap('0')),
        key('', onTap: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)), child: const Icon(Icons.backspace_outlined)),
      ]),
    ]);
  }
}

/// 3x3 pattern lock. Calls [onCompleted] with the dot sequence, e.g. "0-1-2-5-8".
class PatternLock extends StatefulWidget {
  const PatternLock({super.key, required this.onCompleted, this.size = 280, this.error = false});
  final void Function(String pattern) onCompleted;
  final double size;
  final bool error;

  @override
  State<PatternLock> createState() => _PatternLockState();
}

class _PatternLockState extends State<PatternLock> {
  final List<int> _seq = [];
  Offset? _finger;

  Offset _center(int i) {
    final cell = widget.size / 3;
    return Offset((i % 3) * cell + cell / 2, (i ~/ 3) * cell + cell / 2);
  }

  void _hit(Offset p) {
    final r = widget.size / 9;
    for (var i = 0; i < 9; i++) {
      if (!_seq.contains(i) && (p - _center(i)).distance < r) {
        // Pass-through dot between two dots in a straight line is added too (standard Android behaviour).
        if (_seq.isNotEmpty) {
          final a = _seq.last;
          final mid = (a + i) / 2;
          final aligned = (a % 3 + i % 3) % 2 == 0 && (a ~/ 3 + i ~/ 3) % 2 == 0;
          if (aligned && mid == mid.roundToDouble() && !_seq.contains(mid.toInt())) _seq.add(mid.toInt());
        }
        _seq.add(i);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => setState(() {
        _seq.clear();
        _finger = d.localPosition;
        _hit(d.localPosition);
      }),
      onPanUpdate: (d) => setState(() {
        _finger = d.localPosition;
        _hit(d.localPosition);
      }),
      onPanEnd: (_) {
        final p = _seq.join('-');
        setState(() {
          _finger = null;
        });
        if (_seq.length >= 4) {
          widget.onCompleted(p);
        }
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _seq.clear());
        });
      },
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _PatternPainter(List.of(_seq), _finger, _center, widget.error ? X9Colors.error : X9Colors.primary, context.x9.textMuted),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.seq, this.finger, this.center, this.color, this.idle);
  final List<int> seq;
  final Offset? finger;
  final Offset Function(int) center;
  final Color color;

  /// Colour of the dots that are not part of the pattern (theme-dependent).
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < seq.length; i++) {
      canvas.drawLine(center(seq[i - 1]), center(seq[i]), line);
    }
    if (finger != null && seq.isNotEmpty) canvas.drawLine(center(seq.last), finger!, line);
    final r = min(size.width, size.height) / 22;
    for (var i = 0; i < 9; i++) {
      final on = seq.contains(i);
      canvas.drawCircle(center(i), r * (on ? 1.6 : 1), Paint()..color = on ? color : idle.withValues(alpha: 0.45));
      if (on) canvas.drawCircle(center(i), r * 2.6, Paint()..color = color.withValues(alpha: 0.14));
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => true;
}
