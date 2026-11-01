/// Models for the v5 statements (docs/HISTORY-EXPORT-V5.md section 3).
/// Parsing is tolerant: numbers may arrive as int, double or string, and missing fields become empty / 0.
library;

int _i(dynamic v) => v is int ? v : (v is num ? v.round() : (int.tryParse('${v ?? ''}') ?? (double.tryParse('${v ?? ''}')?.round() ?? 0)));

String _s(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final t = v.toString();
  return t.isEmpty ? fallback : t;
}

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

/// Column types the server sends.
class StatementColumnType {
  StatementColumnType._();
  static const text = 'text';
  static const date = 'date';
  static const datetime = 'datetime';
  static const money = 'money';
  static const number = 'number';
  static const percent = 'percent';
  static const status = 'status';
}

/// One entry of `columns[]`: `{key, label, type}`.
class StatementColumn {
  const StatementColumn({required this.key, required this.label, this.type = StatementColumnType.text});

  final String key;
  final String label;
  final String type;

  bool get isMoney => type == StatementColumnType.money;
  bool get isStatus => type == StatementColumnType.status;
  bool get isDate => type == StatementColumnType.date || type == StatementColumnType.datetime;

  factory StatementColumn.fromJson(dynamic json) {
    final m = _m(json);
    final key = _s(m['key']);
    return StatementColumn(
      key: key,
      label: _s(m['label'], humanizeStatementKey(key)),
      type: _s(m['type'], StatementColumnType.text).toLowerCase(),
    );
  }
}

/// "paid_total" -> "Paid total".
String humanizeStatementKey(String key) {
  final t = key.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  if (t.isEmpty) return t;
  return '${t[0].toUpperCase()}${t.substring(1)}';
}

/// One page of a statement: the list response shape shared by every endpoint.
class StatementData {
  const StatementData({
    this.key = '',
    this.title = '',
    this.period = 'month',
    this.from = '',
    this.to = '',
    this.generatedAt = '',
    this.columns = const [],
    this.summary = const {},
    this.rows = const [],
    this.currentPage = 1,
    this.lastPage = 1,
    this.perPage = 25,
    this.total = 0,
  });

  final String key;
  final String title;
  final String period;
  final String from;
  final String to;
  final String generatedAt;
  final List<StatementColumn> columns;

  /// Covers the whole period / filter, not just this page.
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> rows;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  bool get hasMore => currentPage < lastPage;

  factory StatementData.fromJson(dynamic json) {
    final m = _m(json);
    final rawRows = m['rows'] is List ? m['rows'] as List : (m['data'] is List ? m['data'] as List : const []);
    final rawCols = m['columns'] is List ? m['columns'] as List : const [];
    final rows = <Map<String, dynamic>>[
      for (final r in rawRows)
        if (r is Map) _m(r),
    ];
    final cols = <StatementColumn>[
      for (final c in rawCols)
        if (c is Map && _s(c['key']).isNotEmpty) StatementColumn.fromJson(c),
    ];
    final cur = _i(m['current_page']);
    final last = _i(m['last_page']);
    return StatementData(
      key: _s(m['key']),
      title: _s(m['title']),
      period: _s(m['period'], 'month'),
      from: _s(m['from']),
      to: _s(m['to']),
      generatedAt: _s(m['generated_at']),
      columns: cols,
      summary: _m(m['summary']),
      rows: rows,
      currentPage: cur < 1 ? 1 : cur,
      lastPage: last < 1 ? 1 : last,
      perPage: _i(m['per_page']) > 0 ? _i(m['per_page']) : 25,
      total: m['total'] == null ? rows.length : _i(m['total']),
    );
  }
}

/// The filter set of one statement request (period, status, search and the central merchant / user ids).
class StatementQuery {
  const StatementQuery({this.period = 'month', this.from, this.to, this.status = '', this.q = '', this.extra = const {}});

  final String period;

  /// YYYY-MM-DD, only sent for `custom`.
  final String? from;
  final String? to;
  final String status;
  final String q;

  /// e.g. `{merchant_id: '12', user_id: '7'}` for the central statements.
  final Map<String, String> extra;

  StatementQuery copyWith({String? period, String? from, String? to, String? status, String? q, Map<String, String>? extra, bool clearDates = false}) =>
      StatementQuery(
        period: period ?? this.period,
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        status: status ?? this.status,
        q: q ?? this.q,
        extra: extra ?? this.extra,
      );

  Map<String, String> toParams() {
    final p = <String, String>{'period': period};
    if (period == 'custom') {
      if (from != null && from!.isNotEmpty) p['from'] = from!;
      if (to != null && to!.isNotEmpty) p['to'] = to!;
    }
    if (status.isNotEmpty) p['status'] = status;
    if (q.trim().isNotEmpty) p['q'] = q.trim();
    extra.forEach((k, v) {
      if (v.trim().isNotEmpty) p[k] = v.trim();
    });
    return p;
  }
}
