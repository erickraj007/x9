import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../statement_api.dart';
import '../statement_models.dart';
import '../statement_period.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------------------------
// Cell formatting
// ---------------------------------------------------------------------------------------------

const Duration _ist = Duration(hours: 5, minutes: 30);

/// Formats one cell of a statement row by its column type. Money is integer paise.
String statementCellText(StatementColumn c, dynamic v) {
  if (v == null) return '—';
  final raw = v.toString();
  if (raw.isEmpty) return '—';
  switch (c.type) {
    case StatementColumnType.money:
      if (v is num || num.tryParse(raw) != null) return money(asInt(v));
      return raw;
    case StatementColumnType.number:
      final n = v is num ? v : num.tryParse(raw);
      if (n == null) return raw;
      return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
    case StatementColumnType.percent:
      final n = v is num ? v : num.tryParse(raw);
      if (n == null) return raw;
      return '${n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2)}%';
    case StatementColumnType.date:
    case StatementColumnType.datetime:
      return _statementDate(raw, withTime: c.type == StatementColumnType.datetime);
    case StatementColumnType.status:
      return raw.toUpperCase().replaceAll('_', ' ');
  }
  return raw;
}

String _statementDate(String raw, {required bool withTime}) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  // A bare date has no zone: show it as is. A timestamp is shown in IST like the exports.
  final bare = raw.length <= 10;
  final shown = bare ? d : d.toUtc().add(_ist);
  return DateFormat(withTime && !bare ? 'd MMM yyyy, h:mm a' : 'd MMM yyyy').format(shown);
}

bool _summaryIsMoney(String key, List<StatementColumn> columns) {
  for (final c in columns) {
    if (c.key == key) return c.isMoney;
  }
  if (key == 'count' || key.endsWith('_count') || key.contains('percent')) return false;
  return true;
}

// ---------------------------------------------------------------------------------------------
// Period chips
// ---------------------------------------------------------------------------------------------

/// Today / This week / This month / This year / Custom. "Custom" opens a date-range picker limited to the
/// contract (to <= today in IST, at most one year).
class StatementPeriodBar extends StatelessWidget {
  const StatementPeriodBar({super.key, required this.period, required this.onChanged, this.from, this.to});

  final String period;
  final String? from;
  final String? to;
  final void Function(String period, String? from, String? to) onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final today = istDay();
    final last = DateTime(today.year, today.month, today.day);
    final start = parseIsoDate(from);
    final end = parseIsoDate(to);
    DateTimeRange? initial;
    if (start != null && end != null) {
      initial = DateTimeRange(start: DateTime(start.year, start.month, start.day), end: DateTime(end.year, end.month, end.day));
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(last.year - 3, 1, 1),
      lastDate: last,
      initialDateRange: initial,
      helpText: 'Pick up to one year',
    );
    if (picked == null) return;
    final f = formatIsoDate(DateTime.utc(picked.start.year, picked.start.month, picked.start.day));
    final t = formatIsoDate(DateTime.utc(picked.end.year, picked.end.month, picked.end.day));
    try {
      resolveStatementPeriod('custom', from: f, to: t);
    } on InvalidStatementPeriod catch (e) {
      if (context.mounted) showError(context, e.message);
      return;
    }
    onChanged('custom', f, t);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        children: [
          for (final p in StatementPeriods.all)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: p == 'custom' ? const Icon(Icons.date_range_rounded, size: 16) : null,
                label: Text(p == 'custom' && period == 'custom' && from != null && to != null ? '$from → $to' : StatementPeriods.label(p)),
                selected: period == p,
                onSelected: (_) {
                  if (p == 'custom') {
                    _pickCustom(context);
                  } else {
                    onChanged(p, null, null);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Summary tiles
// ---------------------------------------------------------------------------------------------

/// Tiles drawn from the response `summary` map (scalar entries); a `by_status` map becomes a row of small chips.
class StatementSummaryTiles extends StatelessWidget {
  const StatementSummaryTiles({super.key, required this.summary, this.columns = const []});

  final Map<String, dynamic> summary;
  final List<StatementColumn> columns;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final tiles = <Widget>[];
    Map<String, dynamic>? byStatus;
    summary.forEach((k, v) {
      if (v is Map) {
        if (k == 'by_status') byStatus = Map<String, dynamic>.from(v);
        return;
      }
      if (v is List) return;
      final isMoney = _summaryIsMoney(k, columns) && (v is num || num.tryParse('$v') != null);
      final text = v == null ? '—' : (isMoney ? money(asInt(v)) : '$v');
      tiles.add(_Tile(label: humanizeStatementKey(k), value: text));
    });
    if (tiles.isEmpty && byStatus == null) return const SizedBox.shrink();
    final statuses = byStatus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
        if (statuses != null && statuses.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in statuses.entries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(20)),
                child: Text('${e.key.toString().replaceAll('_', ' ')}: ${e.value}', style: TextStyle(color: p.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: X9Text.money(context, size: 16, weight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------------------------

/// One statement row rendered from the response columns: first text column as the title, the first date as the
/// subtitle, the status column as a chip and every other column as a "label value" pair.
class StatementRowCard extends StatelessWidget {
  const StatementRowCard({super.key, required this.columns, required this.row, this.onTap});

  /// v6.8: tap a row (e.g. open the invoice).
  final VoidCallback? onTap;

  final List<StatementColumn> columns;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    StatementColumn? dateCol;
    StatementColumn? titleCol;
    StatementColumn? statusCol;
    for (final c in columns) {
      if (dateCol == null && c.isDate) {
        dateCol = c;
      } else if (statusCol == null && c.isStatus) {
        statusCol = c;
      } else if (titleCol == null && c.type == StatementColumnType.text) {
        titleCol = c;
      }
    }
    final rest = [
      for (final c in columns)
        if (!identical(c, dateCol) && !identical(c, titleCol) && !identical(c, statusCol)) c,
    ];
    final title = titleCol == null ? '' : statementCellText(titleCol, row[titleCol.key]);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (title.isNotEmpty) Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (dateCol != null) Text(statementCellText(dateCol, row[dateCol.key]), style: TextStyle(color: p.textSecondary, fontSize: 12)),
              ]),
            ),
            if (statusCol != null && '${row[statusCol.key] ?? ''}'.isNotEmpty) StatusChip('${row[statusCol.key]}'),
          ]),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 18, runSpacing: 6, children: [
              for (final c in rest)
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(c.label, style: TextStyle(color: p.textMuted, fontSize: 11)),
                  Text(
                    statementCellText(c, row[c.key]),
                    style: c.isMoney ? X9Text.money(context, size: 13.5) : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                ]),
            ]),
          ],
        ]),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------------------------

String _safeFileName(String name) {
  final t = name.split('/').last.split('\\').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return t.isEmpty || t.startsWith('.') ? 'x9-statement' : t;
}

String _mimeFor(String filename) {
  final n = filename.toLowerCase();
  if (n.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.csv')) return 'text/csv';
  if (n.endsWith('.txt')) return 'text/plain';
  return 'application/octet-stream';
}

/// Saves [file] into the app documents directory and returns the saved path.
Future<String> saveStatementFile(StatementFile file) async {
  final dir = await getApplicationDocumentsDirectory();
  final out = File('${dir.path}${Platform.pathSeparator}${_safeFileName(file.filename)}');
  await out.writeAsBytes(file.bytes, flush: true);
  return out.path;
}

/// Downloads the export, saves it to the documents directory and opens the share sheet.
Future<void> exportStatement(StatementScope scope, String key, StatementQuery query, String format, {String? title}) async {
  final file = await StatementApi.export(scope, key, query, format);
  final path = await saveStatementFile(file);
  await Share.shareXFiles(
    [XFile(path, mimeType: _mimeFor(file.filename))],
    subject: title ?? 'X9 statement',
    text: title ?? 'X9 statement',
  );
}

/// Bottom sheet with Excel / PDF / Text / CSV.
Future<void> showStatementExportSheet(
  BuildContext context, {
  required StatementScope scope,
  required String statementKey,
  required StatementQuery query,
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ExportSheet(scope: scope, statementKey: statementKey, query: query, title: title),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.scope, required this.statementKey, required this.query, this.title});
  final StatementScope scope;
  final String statementKey;
  final StatementQuery query;
  final String? title;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  String? _busy;

  static const _options = [
    ['xlsx', 'Excel (.xlsx)', 'Spreadsheet with a totals row and a Summary sheet'],
    ['pdf', 'PDF', 'Print-ready statement'],
    ['txt', 'Text (.txt)', 'Plain fixed-width text'],
    ['csv', 'CSV', 'For accounting software'],
  ];

  IconData _icon(String f) {
    switch (f) {
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'txt':
        return Icons.notes_rounded;
    }
    return Icons.grid_on_rounded;
  }

  Future<void> _run(String format) async {
    if (_busy != null) return;
    setState(() => _busy = format);
    try {
      await exportStatement(widget.scope, widget.statementKey, widget.query, format, title: widget.title);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Export statement', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('All rows of the selected period and filters.', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 10),
          for (final o in _options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icon(o[0]), color: X9Colors.primary),
              title: Text(o[1], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(o[2]),
              trailing: _busy == o[0] ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share_rounded, size: 20),
              enabled: _busy == null,
              onTap: () => _run(o[0]),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// The whole statement view
// ---------------------------------------------------------------------------------------------

/// Period chips + search + summary + paged rows + export, for one statement key. Reloads when [statementKey]
/// or [extraParams] change. Put it inside a Scaffold body (it has its own scrolling).
class StatementView extends StatefulWidget {
  const StatementView({
    super.key,
    required this.scope,
    required this.statementKey,
    this.title,
    this.extraParams = const {},
    this.statuses = const [],
    this.showSearch = true,
    this.emptyTitle = 'No records in this period',
    this.emptySubtitle = 'Try another period or clear the filters.',
    this.onRowTap,
  });

  /// v6.8: called with the tapped row (e.g. open the invoice detail).
  final void Function(Map<String, dynamic> row)? onRowTap;

  final StatementScope scope;
  final String statementKey;
  final String? title;

  /// Extra query params that are always sent (e.g. merchant_id, user_id).
  final Map<String, String> extraParams;

  /// Optional status filter chips (values sent as `status`).
  final List<String> statuses;
  final bool showSearch;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  State<StatementView> createState() => _StatementViewState();
}

class _StatementViewState extends State<StatementView> with AutomaticKeepAliveClientMixin<StatementView> {
  static const _perPage = 25;

  final TextEditingController _search = TextEditingController();
  StatementQuery _q = const StatementQuery();
  StatementData? _head;
  final List<Map<String, dynamic>> _rows = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _token = 0;

  @override
  bool get wantKeepAlive => true;

  StatementQuery get _effective => _q.copyWith(extra: widget.extraParams);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StatementView old) {
    super.didUpdateWidget(old);
    if (old.statementKey != widget.statementKey || !_sameMap(old.extraParams, widget.extraParams)) {
      _q = _q.copyWith(status: '');
      _load();
    }
  }

  bool _sameMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await StatementApi.list(widget.scope, widget.statementKey, _effective, page: 1, perPage: _perPage);
      if (!mounted || token != _token) return;
      setState(() {
        _head = d;
        _rows
          ..clear()
          ..addAll(d.rows);
        _page = d.currentPage;
        _hasMore = d.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore) return;
    final token = _token;
    setState(() => _loadingMore = true);
    try {
      final d = await StatementApi.list(widget.scope, widget.statementKey, _effective, page: _page + 1, perPage: _perPage);
      if (!mounted || token != _token) return;
      setState(() {
        _rows.addAll(d.rows);
        _page = d.currentPage;
        _hasMore = d.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showError(context, e);
    }
  }

  void _setPeriod(String period, String? from, String? to) {
    _q = _q.copyWith(period: period, from: from, to: to, clearDates: period != 'custom');
    _load();
  }

  void _setStatus(String status) {
    _q = _q.copyWith(status: status);
    _load();
  }

  void _submitSearch(String text) {
    _q = _q.copyWith(q: text.trim());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.x9;
    final head = _head;
    final columns = head?.columns ?? const <StatementColumn>[];
    final children = <Widget>[
      StatementPeriodBar(period: _q.period, from: _q.from, to: _q.to, onChanged: _setPeriod),
      if (widget.showSearch)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: _submitSearch,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search reference, number or name',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _submitSearch('');
                      },
                    ),
            ),
          ),
        ),
      if (widget.statuses.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              for (final s in ['', ...widget.statuses])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(s.isEmpty ? 'All' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ')), selected: _q.status == s, onSelected: (_) => _setStatus(s)),
                ),
            ],
          ),
        ),
    ];

    if (_loading && head == null) {
      children.add(const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
    } else if (_error != null && head == null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 24),
        child: ErrorRetry(message: _error is ApiException ? (_error as ApiException).display : 'Could not load the statement.', onRetry: _load),
      ));
    } else if (head != null) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(children: [
          Expanded(
            child: Text(
              '${head.from.isEmpty ? '' : '${head.from} → ${head.to}  ·  '}${head.total} record${head.total == 1 ? '' : 's'}',
              style: TextStyle(color: p.textSecondary, fontSize: 12.5),
            ),
          ),
          FilledButton.tonalIcon(
            // The app theme gives filled buttons an infinite minimum width; inside a Row that must be reset.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: _loading ? null : () => showStatementExportSheet(context, scope: widget.scope, statementKey: widget.statementKey, query: _effective, title: widget.title ?? head.title),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Export'),
          ),
        ]),
      ));
      children.add(const SizedBox(height: 8));
      children.add(StatementSummaryTiles(summary: head.summary, columns: columns));
      if (_error != null) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_error is ApiException ? (_error as ApiException).display : 'Could not refresh.', style: TextStyle(color: p.statusText(X9Colors.error))),
        ));
      }
      if (_rows.isEmpty) {
        children.add(EmptyState(icon: Icons.receipt_long_outlined, title: widget.emptyTitle, subtitle: widget.emptySubtitle));
      } else {
        for (final r in _rows) {
          children.add(Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: StatementRowCard(columns: columns, row: r, onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(r))));
        }
        if (_hasMore) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: OutlinedButton(
              onPressed: _loadingMore ? null : _more,
              child: _loadingMore ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
            ),
          ));
        }
      }
      children.add(const SizedBox(height: 24));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
    );
  }
}

/// A plain screen around one [StatementView] (merchant Sales / Settlement history).
class StatementScreen extends StatelessWidget {
  const StatementScreen({super.key, required this.scope, required this.statementKey, required this.title, this.statuses = const [], this.onRowTap});

  final void Function(BuildContext context, Map<String, dynamic> row)? onRowTap;

  final StatementScope scope;
  final String statementKey;
  final String title;
  final List<String> statuses;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StatementView(
        scope: scope,
        statementKey: statementKey,
        title: title,
        statuses: statuses,
        onRowTap: onRowTap == null ? null : (row) => onRowTap!(context, row),
      ),
    );
  }
}
