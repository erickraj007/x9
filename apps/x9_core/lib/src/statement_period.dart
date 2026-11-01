/// Period resolution for statements. Mirrors the contract rules of docs/HISTORY-EXPORT-V5.md section 2:
/// every period is resolved in Asia/Kolkata (IST, UTC+05:30, no DST) and the server echoes `{period, from, to}`.
library;

/// Raised for an invalid `custom` range (the server answers 422 INVALID_PERIOD for the same cases).
class InvalidStatementPeriod implements Exception {
  InvalidStatementPeriod(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A resolved period: dates are `YYYY-MM-DD`, inclusive on both ends.
class ResolvedPeriod {
  const ResolvedPeriod(this.period, this.from, this.to);
  final String period;
  final String from;
  final String to;

  @override
  bool operator ==(Object other) => other is ResolvedPeriod && other.period == period && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(period, from, to);

  @override
  String toString() => '$period $from..$to';
}

class StatementPeriods {
  StatementPeriods._();

  /// Chip order.
  static const all = ['today', 'week', 'month', 'year', 'custom'];

  /// Default when the period is missing.
  static const defaultPeriod = 'month';

  /// Longest custom range, counted as the difference between the two dates (366 days inclusive on the server;
  /// 365 here is safe under either reading of "span <= 366 days").
  static const maxCustomDays = 365;

  static String label(String period) {
    switch (period) {
      case 'today':
        return 'Today';
      case 'week':
        return 'This week';
      case 'month':
        return 'This month';
      case 'year':
        return 'This year';
      case 'custom':
        return 'Custom';
    }
    return period;
  }
}

const Duration _istOffset = Duration(hours: 5, minutes: 30);

/// The calendar day in IST of [instant] (default: now), as a UTC-midnight DateTime so day maths has no DST surprises.
DateTime istDay([DateTime? instant]) {
  final shifted = (instant ?? DateTime.now()).toUtc().add(_istOffset);
  return DateTime.utc(shifted.year, shifted.month, shifted.day);
}

/// `YYYY-MM-DD` of a date.
String formatIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Strict `YYYY-MM-DD` -> UTC-midnight DateTime (null for anything else, including 2026-02-31).
DateTime? parseIsoDate(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final dt = DateTime.utc(y, mo, d);
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}

/// Resolves [period] in IST. [now] is the clock (tests pass a fixed instant); `custom` needs [from] and [to].
/// Throws [InvalidStatementPeriod] for a bad custom range: not dates, from > to, a span over a year, or `to` in the future.
ResolvedPeriod resolveStatementPeriod(String? period, {String? from, String? to, DateTime? now}) {
  final today = istDay(now);
  final p = (period == null || period.isEmpty) ? StatementPeriods.defaultPeriod : period;
  switch (p) {
    case 'today':
      return ResolvedPeriod(p, formatIsoDate(today), formatIsoDate(today));
    case 'week':
      final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
      return ResolvedPeriod(p, formatIsoDate(monday), formatIsoDate(today));
    case 'month':
      return ResolvedPeriod(p, formatIsoDate(DateTime.utc(today.year, today.month, 1)), formatIsoDate(today));
    case 'year':
      return ResolvedPeriod(p, formatIsoDate(DateTime.utc(today.year, 1, 1)), formatIsoDate(today));
    case 'custom':
      final f = parseIsoDate(from);
      final t = parseIsoDate(to);
      if (f == null || t == null) throw InvalidStatementPeriod('Pick a start and an end date.');
      if (f.isAfter(t)) throw InvalidStatementPeriod('The start date must be on or before the end date.');
      if (t.isAfter(today)) throw InvalidStatementPeriod('The end date cannot be in the future.');
      if (t.difference(f).inDays > StatementPeriods.maxCustomDays) throw InvalidStatementPeriod('Pick a range of at most one year.');
      return ResolvedPeriod(p, formatIsoDate(f), formatIsoDate(t));
  }
  throw InvalidStatementPeriod('Unknown period "$p".');
}

/// Whether a row's business timestamp falls in [p], judged on its IST calendar day (vector P5).
bool statementRowInPeriod(DateTime instant, ResolvedPeriod p) {
  final day = formatIsoDate(istDay(instant));
  return day.compareTo(p.from) >= 0 && day.compareTo(p.to) <= 0;
}
