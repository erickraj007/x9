import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../services/location.dart';
import '../../services/signup_location.dart';
import '../../util/distance_confirm.dart';
import '../../util/helpers.dart';
import '../appointments/book_appointment.dart';
import '../merchant/merchant_screen.dart' show finalPriceOf;

/// v6.10: order a product / service from a shop (delivery to the saved location, or pick up), or schedule an appointment.
/// The shop sees the order / appointment in its app straight away.
Future<void> showOrderSheet(
  BuildContext context, {
  required String merchantUuid,
  required String shopName,
  required Map<String, dynamic> product,
  dynamic distanceKm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OrderSheet(merchantUuid: merchantUuid, shopName: shopName, product: product, distanceKm: distanceKm),
  );
}

/// Saves the phone's current position as a delivery address (Set location). Returns the saved address or null.
Future<Map<String, dynamic>?> setDeliveryLocation(BuildContext context) async {
  try {
    final fix = await locateForSignup();
    if (fix == null) {
      if (context.mounted) showError(context, 'Could not read your location. Turn on location and try again.');
      return null;
    }
    final place = await reverseGeocodeForSignup(fix.lat, fix.lng);
    final r = await Api.instance.post('/app/addresses', {
      'label': 'Home',
      'address': (place?.address ?? '').length >= 5 ? place!.address : 'Near ${fix.lat.toStringAsFixed(5)}, ${fix.lng.toStringAsFixed(5)}',
      if ((place?.city ?? '').isNotEmpty) 'city': place!.city,
      if ((place?.pincode ?? '').isNotEmpty) 'pincode': place!.pincode,
      'lat': fix.lat,
      'lng': fix.lng,
      'is_default': true,
    });
    return asMap(r);
  } catch (e) {
    if (context.mounted) showFriendlyError(context, e);
    return null;
  }
}

class _OrderSheet extends StatefulWidget {
  const _OrderSheet({required this.merchantUuid, required this.shopName, required this.product, this.distanceKm});
  final String merchantUuid;
  final String shopName;
  final Map<String, dynamic> product;
  final dynamic distanceKm;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  int _qty = 1;
  bool _delivery = true;
  bool _busy = false;
  bool _loadingAddr = true;
  Map<String, dynamic>? _addr;
  final _note = TextEditingController();

  int get _unit => finalPriceOf(widget.product);
  int get _id => asInt(widget.product['id']);

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadAddress() async {
    try {
      final r = asList(await Api.instance.get('/app/addresses')).map(asMap).toList();
      if (mounted) setState(() => _addr = r.isEmpty ? null : r.first);
    } catch (_) {}
    if (mounted) setState(() => _loadingAddr = false);
  }

  Future<void> _setLocation() async {
    setState(() => _loadingAddr = true);
    final a = await setDeliveryLocation(context);
    if (!mounted) return;
    setState(() {
      if (a != null && a.isNotEmpty) _addr = a;
      _loadingAddr = false;
    });
  }

  Future<void> _order() async {
    if (_delivery && _addr == null) {
      showError(context, 'Set your delivery location first.');
      return;
    }
    if (!await confirmDistance(context, shopName: widget.shopName, distanceKm: widget.distanceKm, what: 'order') || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.instance.post('/app/orders', {
        'merchant_uuid': widget.merchantUuid,
        'items': [
          {'product_id': _id, 'qty': _qty}
        ],
        'fulfilment': _delivery ? 'DELIVERY' : 'PICKUP',
        if (_delivery && _addr != null) 'address_id': asInt(_addr!['id']),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      showOk(context, 'Order sent to ${widget.shopName}. You will see their reply in My orders.');
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
    final name = str(widget.product['name'], 'Item');
    final service = str(widget.product['type']).toUpperCase() == 'SERVICE';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(service ? 'Book $name' : 'Order $name', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(widget.shopName, style: TextStyle(color: p.textSecondary)),
          const SizedBox(height: 14),
          Row(children: [
            Text(money(_unit, compact: true), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const Spacer(),
            IconButton(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
            Text('$_qty', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            IconButton(onPressed: _qty < 99 ? () => setState(() => _qty++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
          ]),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, icon: Icon(Icons.delivery_dining_rounded), label: Text('Delivery')),
              ButtonSegment(value: false, icon: Icon(Icons.storefront_rounded), label: Text('Pick up')),
            ],
            selected: {_delivery},
            onSelectionChanged: (v) => setState(() => _delivery = v.first),
          ),
          if (_delivery) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: _loadingAddr
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.location_on_rounded, color: X9Colors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_addr == null ? 'No delivery location yet' : 'Deliver to ${str(_addr!['label'], 'Home')}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                      if (_addr != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(str(_addr!['address']), style: const TextStyle(fontSize: 13))),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _setLocation,
                          icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                          label: Text(_addr == null ? 'Set location' : 'Use my current location'),
                        ),
                      ),
                    ]),
            ),
          ],
          const SizedBox(height: 10),
          TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(labelText: 'Note for the shop (optional)')),
          Text('Total ${money(_unit * _qty, compact: true)} · pay the shop on ${_delivery ? 'delivery' : 'pick-up'}', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : _order, child: Text(_busy ? 'Sending…' : (service ? 'Request service' : 'Place order'))),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              showBookAppointment(
                context,
                merchantUuid: widget.merchantUuid,
                shopName: widget.shopName,
                distanceKm: widget.distanceKm,
                productId: _id,
                itemName: name,
                fromCity: LocationService.instance.city,
              );
            },
            icon: const Icon(Icons.event_available_rounded, size: 18),
            label: const Text('Schedule an appointment instead'),
          ),
        ]),
      ),
    );
  }
}
