import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';

/// Change the prepaid card PIN: new 4-digit PIN twice → unlock → POST /app/cards/{id}/pin (signed, amount 0).
class CardPinScreen extends StatefulWidget {
  const CardPinScreen({super.key, required this.cardId});
  final int cardId;

  @override
  State<CardPinScreen> createState() => _CardPinScreenState();
}

class _CardPinScreenState extends State<CardPinScreen> {
  String? _first;
  String? _error;
  bool _busy = false;

  static const _weak = {'0000', '1111', '2222', '3333', '4444', '5555', '6666', '7777', '8888', '9999', '1234', '4321', '0123'};

  Future<void> _entered(String pin) async {
    if (_busy) return;
    if (_first == null) {
      if (_weak.contains(pin)) {
        setState(() => _error = 'Too easy to guess. Choose another PIN.');
        return;
      }
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = 'PINs did not match. Start again.';
      });
      return;
    }
    final ok = await AppLock.instance.confirm(context, reason: 'Change card PIN');
    if (!mounted) return;
    if (!ok) {
      setState(() => _first = null);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = asMap(await Api.instance.money('POST', '/app/cards/${widget.cardId}/pin', {'new_pin': pin}, amount: 0));
      if (!mounted) return;
      final status = str(r['status'], 'SUCCESS').toUpperCase();
      if (status == 'FAILED') throw Exception(str(r['failure_reason'], 'The card provider did not accept the new PIN.'));
      showOk(context, 'Card PIN changed');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showFriendlyError(context, e);
      setState(() {
        _first = null;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change card PIN')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Icon(Icons.password_rounded, size: 40, color: X9Colors.primary),
              const SizedBox(height: 10),
              Text(_first == null ? 'Enter a new 4-digit card PIN' : 'Enter the new PIN again', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Used at ATMs and card machines.', style: TextStyle(color: context.x9.textSecondary)),
              const SizedBox(height: 20),
              if (_busy)
                const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
              else
                PinPad(key: ValueKey(_first == null ? 'first' : 'second'), length: 4, onCompleted: _entered, error: _error),
            ]),
          ),
        ),
      ),
    );
  }
}
