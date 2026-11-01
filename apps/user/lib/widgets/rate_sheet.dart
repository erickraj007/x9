import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

/// Rate & review a merchant after a successful payment (POST /app/feedback).
/// [transactionId] is the numeric transaction id. Returns true when saved.
Future<bool> showRateSheet(BuildContext context, {required int transactionId, String? merchantName}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _RateBody(transactionId: transactionId, merchantName: merchantName),
    ),
  );
  if (ok == true && context.mounted) showOk(context, 'Thanks for your review!');
  return ok == true;
}

class _RateBody extends StatefulWidget {
  const _RateBody({required this.transactionId, this.merchantName});
  final int transactionId;
  final String? merchantName;

  @override
  State<_RateBody> createState() => _RateBodyState();
}

class _RateBodyState extends State<_RateBody> {
  int _rating = 0;
  final _text = TextEditingController();

  static const _labels = ['', 'Poor', 'Below average', 'Good', 'Very good', 'Excellent'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_rating == 0) throw Exception('Tap a star to rate.');
    await Api.instance.post('/app/feedback', {
      'transaction_id': widget.transactionId,
      'rating': _rating,
      if (_text.text.trim().isNotEmpty) 'review': _text.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            widget.merchantName == null || widget.merchantName!.isEmpty ? 'How was your experience?' : 'Rate ${widget.merchantName}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _rating = i);
                },
                child: AnimatedScale(
                  scale: _rating >= i ? 1.15 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(_rating >= i ? Icons.star_rounded : Icons.star_outline_rounded, size: 44, color: X9Colors.primary),
                  ),
                ),
              ),
          ]),
          SizedBox(
            height: 24,
            child: Center(child: Text(_labels[_rating], style: TextStyle(fontWeight: FontWeight.w700, color: context.x9.textSecondary))),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(hintText: 'Tell others about the shop (optional)'),
          ),
          const SizedBox(height: 8),
          BusyButton(label: 'Submit review', icon: Icons.send_rounded, onPressed: _save),
        ]),
      ),
    );
  }
}
