import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/distance_confirm.dart';
import '../../util/helpers.dart';
import '../../util/travel.dart';

/// Fix an appointment: shows the travel time from the person's location, then date + time and a note.
/// [distanceKm] comes from the shop card (distance from the phone, also when another city was searched).
Future<void> showBookAppointment(
  BuildContext context, {
  required String merchantUuid,
  required String shopName,
  dynamic distanceKm,
  int? locationId,
  int? productId,
  String? itemName,
  String? fromCity,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BookSheet(
      merchantUuid: merchantUuid,
      shopName: shopName,
      distanceKm: distanceKm,
      locationId: locationId,
      productId: productId,
      itemName: itemName,
      fromCity: fromCity,
    ),
  );
}

class _BookSheet extends StatefulWidget {
  const _BookSheet({required this.merchantUuid, required this.shopName, this.distanceKm, this.locationId, this.productId, this.itemName, this.fromCity});
  final String merchantUuid;
  final String shopName;
  final dynamic distanceKm;
  final int? locationId;
  final int? productId;
  final String? itemName;
  final String? fromCity;

  @override
  State<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends State<_BookSheet> {
  late DateTime _at;
  final _note = TextEditingController();
  bool _busy = false;

  int get _travel {
    final d = widget.distanceKm == null ? 0.0 : asDouble(widget.distanceKm);
    return d > 0 ? travelMinutes(d) : 0;
  }

  @override
  void initState() {
    super.initState();
    // earliest sensible time: leave in 30 min + travel time, rounded up to the next 15 minutes
    final t = DateTime.now().add(Duration(minutes: 30 + _travel));
    final add = (15 - t.minute % 15) % 15;
    _at = DateTime(t.year, t.month, t.day, t.hour, t.minute).add(Duration(minutes: add));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  Future<void> _submit() async {
    if (_at.isBefore(DateTime.now().add(const Duration(minutes: 10)))) {
      showError(context, 'Choose a time at least 10 minutes from now.');
      return;
    }
    if (!await confirmDistance(context, shopName: widget.shopName, distanceKm: widget.distanceKm, what: 'appointment request') || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.instance.post('/app/appointments', {
        'merchant_uuid': widget.merchantUuid,
        'scheduled_at': _at.toUtc().toIso8601String(),
        if (widget.locationId != null) 'location_id': widget.locationId,
        if (widget.productId != null) 'product_id': widget.productId,
        if (_travel > 0) 'travel_minutes': _travel,
        if ((widget.fromCity ?? '').isNotEmpty) 'from_city': widget.fromCity,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      showOk(context, 'Appointment requested. ${widget.shopName} will confirm.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFriendlyError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final eta = _travel > 0 ? 'About ${fmtMinutes(_travel)} away. Leave by ${fmtClock(_at.subtract(Duration(minutes: _travel)))} to arrive on time.' : '';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Fix an appointment', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(widget.itemName == null ? widget.shopName : '${widget.itemName} · ${widget.shopName}', style: TextStyle(color: p.textSecondary)),
          if (eta.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.directions_car_rounded, color: X9Colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(eta, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event_rounded), label: Text('${_at.day}/${_at.month}/${_at.year}'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded), label: Text(fmtClock(_at)))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(labelText: 'Note for the shop (optional)')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Sending…' : 'Request appointment')),
        ]),
      ),
    );
  }
}
