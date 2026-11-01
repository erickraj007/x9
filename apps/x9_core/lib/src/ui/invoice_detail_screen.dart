import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Full invoice: shop, items, totals and payment details (mode, UTR, transaction id, payer) with a Share button.
/// [merchantScope] true -> `/merchant/invoice-detail/{number}`, else the central `/admin/...` route.
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.number, this.merchantScope = true});

  final String number;
  final bool merchantScope;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, dynamic>? _d;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.instance.get('/${widget.merchantScope ? 'merchant' : 'admin'}/invoice-detail/${Uri.encodeComponent(widget.number)}');
      if (!mounted) return;
      setState(() {
        _d = r is Map ? Map<String, dynamic>.from(r) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Widget _row(String k, String v, {bool mono = false}) {
    if (v.isEmpty || v == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 118, child: Text(k, style: TextStyle(color: context.x9.textSecondary, fontSize: 13))),
        Expanded(child: SelectableText(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: mono ? 'monospace' : null))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${widget.number}'),
        actions: [
          if (d != null)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_rounded),
              onPressed: () => Share.share('${d['share_text'] ?? ''}', subject: 'Invoice ${widget.number}'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error is ApiException ? (_error as ApiException).display : 'Could not load this invoice.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  ),
                )
              : _body(d),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share invoice'),
                  onPressed: () => Share.share('${d['share_text'] ?? ''}', subject: 'Invoice ${widget.number}'),
                ),
              ),
            ),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final shop = _m(d['merchant']);
    final t = _m(d['totals']);
    final p = _m(d['payment']);
    final cust = _m(d['customer']);
    final items = d['items'] is List ? (d['items'] as List).map(_m).toList() : <Map<String, dynamic>>[];
    final paid = '${p['status']}' == 'PAID';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text('${shop['shop_name'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          StatusChip('${d['status']}'),
        ]),
        if ('${shop['address'] ?? ''}'.isNotEmpty) Text('${shop['address']}', style: TextStyle(color: context.x9.textSecondary, fontSize: 13)),
        const SizedBox(height: 4),
        Text(fmtDate(d['created_at']), style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text('${i['quantity']} × ${i['name']}')),
                    Text(money(asInt(i['line_total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              if (items.isEmpty) Text('${d['description'] ?? ''}'),
              const Divider(height: 20),
              _line('Gross', asInt(t['gross'])),
              if (asInt(t['offer']) > 0) _line('Offer', -asInt(t['offer'])),
              if (asInt(t['tax']) > 0) _line('Tax', asInt(t['tax'])),
              _line('Total', asInt(t['final']), bold: true),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Payment details', style: TextStyle(fontWeight: FontWeight.w700))),
                Icon(paid ? Icons.check_circle_rounded : Icons.schedule_rounded, color: paid ? X9Colors.success : context.x9.textSecondary, size: 20),
              ]),
              const SizedBox(height: 6),
              _row('Status', '${p['status'] ?? ''}'),
              _row('Mode', '${p['mode'] ?? ''}'),
              _row('UTR', '${p['utr'] ?? ''}', mono: true),
              _row('Transaction ID', '${p['transaction_id'] ?? ''}', mono: true),
              _row('Receipt', '${p['receipt_no'] ?? ''}'),
              _row('Paid at', p['paid_at'] == null ? '' : fmtDate(p['paid_at'])),
              _row('Paid by', [p['payer_name'], p['payer_vpa']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
              if (cust.isNotEmpty) _row('Customer', '${cust['name'] ?? ''} ${cust['mobile'] ?? ''}'.trim()),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _line(String k, int paise, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
          Text(paise < 0 ? '-${money(-paise)}' : money(paise), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 16 : 14)),
        ]),
      );
}
