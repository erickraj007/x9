import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';
import '../../widgets/bits.dart';
import '../../widgets/rate_sheet.dart';
import '../../widgets/receipt_view.dart';
import '../../widgets/skeleton.dart';

/// Receipt (GET /app/receipts/{id}) or transaction detail (GET /app/transactions/{id}),
/// with "Save to gallery", Share and Rate.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, this.receiptId, this.transactionId, this.initial});
  final int? receiptId;
  final int? transactionId;

  /// Receipt already in hand (from the payment response); shown while the fresh copy loads.
  final Map<String, dynamic>? initial;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final GlobalKey _shot = GlobalKey();
  Map<String, dynamic>? _receipt;
  Map<String, dynamic>? _txn;
  Object? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && asMap(init['payload']).isNotEmpty) _receipt = init;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.receiptId != null) {
        _receipt = asMap(await Api.instance.get('/app/receipts/${widget.receiptId}'));
      } else if (widget.transactionId != null) {
        final t = asMap(await Api.instance.get('/app/transactions/${widget.transactionId}'));
        _txn = t;
        final r = asMap(t['receipt']);
        if (asMap(r['payload']).isNotEmpty) {
          _receipt = r;
        } else if (intOrNull(r['id']) != null) {
          _receipt = asMap(await Api.instance.get('/app/receipts/${r['id']}'));
        }
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic> get _payload => asMap(_receipt?['payload']);

  int? get _numericTxnId => widget.transactionId ?? intOrNull(_receipt?['transaction_id']) ?? intOrNull(_txn?['id']);

  Future<Uint8List?> _png() async {
    final ctx = _shot.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  String get _fileName => 'X9-receipt-${str(_receipt?['number'], str(_payload['transaction_id'], '${DateTime.now().millisecondsSinceEpoch}'))}';

  Future<void> _saveToGallery() async {
    setState(() => _saving = true);
    try {
      final bytes = await _png();
      if (bytes == null) throw Exception('Could not render the receipt.');
      await Gal.putImageBytes(bytes, album: 'X9');
      if (mounted) showOk(context, 'Receipt saved to your gallery (X9 album)');
    } on GalException catch (e) {
      if (mounted) showError(context, 'Could not save to gallery (${e.type.name}). Allow photo access and try again.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    try {
      final bytes = await _png();
      if (bytes == null) throw Exception('Could not render the receipt.');
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$_fileName.png');
      await f.writeAsBytes(bytes, flush: true);
      final shop = str(asMap(_payload['merchant'])['shop_name'], 'merchant');
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: 'X9 payment receipt — ${money(asInt(_payload['final_amount']))} to $shop');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReceipt = _payload.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(hasReceipt ? 'Receipt' : 'Transaction')),
      body: _body(hasReceipt),
      bottomNavigationBar: hasReceipt
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _saveToGallery,
                      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton.icon(onPressed: _share, icon: const Icon(Icons.share_rounded), label: const Text('Share'))),
                ]),
              ),
            )
          : null,
    );
  }

  Widget _body(bool hasReceipt) {
    if (_loading && _receipt == null && _txn == null) {
      return ListView(padding: const EdgeInsets.all(16), children: const [Skeleton(height: 420, radius: 22)]);
    }
    if (_error != null && _receipt == null && _txn == null) return ErrorRetry(message: friendlyError(_error!), onRetry: _load);
    final txnId = _numericTxnId;
    final success = hasReceipt || str(_txn?['status']).toUpperCase() == 'SUCCESS';
    final shop = hasReceipt ? str(asMap(_payload['merchant'])['shop_name']) : str(asMap(_txn?['merchant'])['shop_name']);
    final canRate = success && txnId != null && shop.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (hasReceipt)
          RepaintBoundary(
            key: _shot,
            child: Container(
              color: X9Colors.lightBackground, // the saved image is always on white
              padding: const EdgeInsets.all(4),
              child: ReceiptView(payload: _payload, number: str(_receipt?['number']), cashbackCredited: asInt(_receipt?['cashback_credited'])),
            ),
          )
        else
          _txnCard(),
        if (canRate) ...[
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.star_rounded, color: X9Colors.primary, size: 30),
              title: Text('Rate $shop'),
              subtitle: const Text('Help others find great shops'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showRateSheet(context, transactionId: txnId!, merchantName: shop),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _txnCard() {
    final t = _txn ?? const <String, dynamic>{};
    final status = str(t['status']).toUpperCase();
    final m = asMap(t['merchant']);
    final kind = str(t['kind']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: StatusChip(status)),
          const SizedBox(height: 10),
          Text(money(asInt(t['final_amount'])), textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
          if (str(m['shop_name']).isNotEmpty) Text(str(m['shop_name']), textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary)),
          const SizedBox(height: 14),
          const DashedLine(),
          const SizedBox(height: 8),
          if (kind.isNotEmpty) KvRow('Type', kind.replaceAll('_', ' ')),
          if (str(t['payment_mode']).isNotEmpty) KvRow('Mode', str(t['payment_mode'])),
          if (asInt(t['gross_amount']) > 0) KvRow('Amount', money(asInt(t['gross_amount']))),
          if (asInt(t['offer_amount']) > 0) KvRow('Offer', '− ${money(asInt(t['offer_amount']))}', valueColor: context.x9.statusText(X9Colors.success)),
          KvRow('Date', fmtDate(t['completed_at'] ?? t['created_at'])),
          if (str(t['transaction_id']).isNotEmpty) KvRow('Transaction ID', str(t['transaction_id'])),
          if (str(asMap(t['invoice'])['number']).isNotEmpty) KvRow('Invoice', str(asMap(t['invoice'])['number'])),
          if (str(t['failure_reason']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(str(t['failure_reason']), style: TextStyle(color: context.x9.statusText(X9Colors.error))),
          ],
        ]),
      ),
    );
  }
}
