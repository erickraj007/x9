import 'package:flutter_test/flutter_test.dart';
import 'package:x9_core/src/offer_math.dart';

// Contract vectors V1-V4 from docs/OFFERS-V3.md (all money in paise, both programs at 0 %).
void main() {
  group('percentOf (round half up)', () {
    test('exact', () {
      expect(percentOf(80000, 5), 4000);
      expect(percentOf(80000, 0), 0);
      expect(percentOf(0, 10), 0);
    });
    test('half goes up', () {
      expect(percentOf(250, 1), 3); // 2.5
      expect(percentOf(150, 1), 2); // 1.5
      expect(percentOf(249, 1), 2); // 2.49
      expect(percentOf(1000, 2.5), 25);
      expect(percentOf(10, 0.07), 0); // 0.007
    });
  });

  group('V1 - RICE 590, flat 10', () {
    test('offer 1000 -> pay balance 58000', () {
      final l = lineMath(mrp: 59000, mode: 'FLAT', value: 1000);
      expect(l.offer, 1000);
      expect(l.payBalance, 58000);
    });
    test('flat is per unit', () {
      final l = lineMath(mrp: 59000, qty: 3, mode: 'FLAT', value: 1000);
      expect(l.offer, 3000);
      expect(l.payBalance, 174000);
    });
    test('flat never exceeds the line', () {
      expect(lineMath(mrp: 500, mode: 'FLAT', value: 900).payBalance, 0);
    });
  });

  group('percent examples', () {
    test('RICE 800 at 5% -> 760', () {
      final l = lineMath(mrp: 80000, mode: 'PERCENT', value: 5);
      expect(l.offer, 4000);
      expect(l.payBalance, 76000);
    });
  });

  group('V2 - two PRODUCT lines, GST 5%', () {
    test('taxable 134000, GST 6700, final 140700', () {
      final a = lineMath(mrp: 80000, mode: 'PERCENT', value: 5, gstPercent: 5);
      final b = lineMath(mrp: 59000, mode: 'FLAT', value: 1000, gstPercent: 5);
      expect(a.payBalance, 76000);
      expect(b.payBalance, 58000);
      final t = billTotals([a, b]);
      expect(t.mrpTotal, 139000);
      expect(t.offerTotal, 5000);
      expect(t.taxableValue, 134000);
      expect(t.gstTotal, 6700);
      expect(t.grandTotal, 140700);
    });
  });

  group('V3 - CASHBACK FLAT 10000 on RICE 80000, GST 5%', () {
    test('customer pays 84000, cashback 10000', () {
      final l = lineMath(mrp: 80000, gstPercent: 5);
      final t = billTotals([l]);
      expect(t.mrpTotal, 80000);
      expect(t.offerTotal, 0);
      expect(t.gstTotal, 4000);
      expect(t.grandTotal, 84000);
      expect(cashbackAmount(mode: 'FLAT', value: 10000, eligibleMrp: 80000), 10000);
    });
    test('flat cashback is limited to the eligible MRP', () {
      expect(cashbackAmount(mode: 'FLAT', value: 10000, eligibleMrp: 6000), 6000);
    });
  });

  group('V4 - CASHBACK PERCENT 5, max 3000', () {
    test('4000 capped to 3000', () {
      expect(cashbackAmount(mode: 'PERCENT', value: 5, eligibleMrp: 80000, maxCashback: 3000), 3000);
    });
    test('uncapped is 4000', () {
      expect(cashbackAmount(mode: 'PERCENT', value: 5, eligibleMrp: 80000), 4000);
    });
    test('budget left caps it too', () {
      expect(cashbackAmount(mode: 'PERCENT', value: 5, eligibleMrp: 80000, maxCashback: 3000, budgetRemaining: 1200), 1200);
      expect(cashbackAmount(mode: 'PERCENT', value: 5, eligibleMrp: 80000, budgetRemaining: 0), 0);
    });
  });

  group('GST inclusive', () {
    test('105.00 inclusive of 5% holds 5.00 of GST', () {
      final g = gstOnNet(10500, 5, inclusive: true);
      expect(g.tax, 500);
      expect(g.total, 10500);
    });
  });
}
