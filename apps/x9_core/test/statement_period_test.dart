import 'package:flutter_test/flutter_test.dart';
import 'package:x9_core/src/statement_period.dart';

// Contract vectors P1-P6 from docs/HISTORY-EXPORT-V5.md section 5.
// Fixed clock: now = Tue 2026-10-13 10:00 IST = 2026-10-13 04:30 UTC.
void main() {
  final now = DateTime.utc(2026, 10, 13, 4, 30);

  ResolvedPeriod r(String p, {String? from, String? to}) => resolveStatementPeriod(p, from: from, to: to, now: now);

  group('P - periods', () {
    test('P1 today -> 2026-10-13..2026-10-13', () {
      expect(r('today'), const ResolvedPeriod('today', '2026-10-13', '2026-10-13'));
    });
    test('P2 week -> Monday 2026-10-12..2026-10-13', () {
      expect(r('week'), const ResolvedPeriod('week', '2026-10-12', '2026-10-13'));
    });
    test('P3 month -> 2026-10-01..2026-10-13', () {
      expect(r('month'), const ResolvedPeriod('month', '2026-10-01', '2026-10-13'));
    });
    test('P4 year -> 2026-01-01..2026-10-13', () {
      expect(r('year'), const ResolvedPeriod('year', '2026-01-01', '2026-10-13'));
    });
    test('missing period defaults to month', () {
      expect(resolveStatementPeriod(null, now: now), const ResolvedPeriod('month', '2026-10-01', '2026-10-13'));
    });
    test('IST day rolls over at 18:30 UTC', () {
      // 2026-10-12 19:00 UTC is already 2026-10-13 in IST.
      expect(formatIsoDate(istDay(DateTime.utc(2026, 10, 12, 19, 0))), '2026-10-13');
      expect(formatIsoDate(istDay(DateTime.utc(2026, 10, 12, 18, 29))), '2026-10-12');
    });
    test('P5 row at 2026-10-12 19:00 UTC is in today, 18:29 UTC is not', () {
      final today = r('today');
      expect(statementRowInPeriod(DateTime.utc(2026, 10, 12, 19, 0), today), isTrue);
      expect(statementRowInPeriod(DateTime.utc(2026, 10, 12, 18, 29), today), isFalse);
    });
    test('P6 custom: valid range passes', () {
      expect(r('custom', from: '2026-09-01', to: '2026-10-13'), const ResolvedPeriod('custom', '2026-09-01', '2026-10-13'));
    });
    test('P6 custom from in the future is rejected', () {
      expect(() => r('custom', from: '2026-10-14', to: '2026-10-14'), throwsA(isA<InvalidStatementPeriod>()));
    });
    test('P6 custom span of 400 days is rejected', () {
      expect(() => r('custom', from: '2025-09-09', to: '2026-10-13'), throwsA(isA<InvalidStatementPeriod>()));
    });
    test('P6 custom from after to is rejected', () {
      expect(() => r('custom', from: '2026-10-10', to: '2026-10-01'), throwsA(isA<InvalidStatementPeriod>()));
    });
    test('custom needs real dates', () {
      expect(() => r('custom', from: '2026-02-31', to: '2026-03-02'), throwsA(isA<InvalidStatementPeriod>()));
      expect(() => r('custom'), throwsA(isA<InvalidStatementPeriod>()));
    });
  });
}
