import 'package:flutter_test/flutter_test.dart';
import 'package:x9_core/src/card_math.dart';

// Contract vectors F1-F4, W1, W2, C1, C2 from docs/PREPAID-CARD-V4.md section 7 (all money in paise).
void main() {
  CardFeeResult loadFee(int base, {num waiver = 0}) =>
      cardFee(mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000, gstPercent: 18, base: base, waiverPercent: waiver);

  group('F - fee rules', () {
    test('F1 load 100000 -> fee 1000, gst 180, total 1180, you pay 101180', () {
      final r = loadFee(100000);
      expect(r.fee, 1000);
      expect(r.gst, 180);
      expect(r.totalFee, 1180);
      final q = cardLoadQuote(amount: 100000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000);
      expect(q.youPay, 101180);
      expect(q.cardCredit, 100000);
    });
    test('F2 load 20000 -> raw 200 raised to min 500, gst 90, total 590, you pay 20590', () {
      final r = loadFee(20000);
      expect(r.raw, 500);
      expect(r.fee, 500);
      expect(r.gst, 90);
      expect(r.totalFee, 590);
      expect(cardLoadQuote(amount: 20000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000).youPay, 20590);
    });
    test('F3 load 1000000 -> raw 10000 capped to max 5000, gst 900, total 5900, you pay 1005900', () {
      final r = loadFee(1000000);
      expect(r.fee, 5000);
      expect(r.gst, 900);
      expect(r.totalFee, 5900);
      expect(cardLoadQuote(amount: 1000000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000).youPay, 1005900);
    });
    test('F4 ISSUE_PHYSICAL FLAT 9900, gst 18 -> gst 1782, total 11682', () {
      final r = cardFee(mode: 'FLAT', value: 9900, gstPercent: 18);
      expect(r.fee, 9900);
      expect(r.gst, 1782);
      expect(r.totalFee, 11682);
    });
    test('no rule means no fee', () {
      final q = cardLoadQuote(amount: 100000);
      expect(q.totalFee, 0);
      expect(q.youPay, 100000);
    });
  });

  group('W - fee waiver', () {
    const w1 = CardOfferRule(type: 'FEE_WAIVER', appliesTo: 'LOAD', value: 100, minAmount: 50000);
    const w2 = CardOfferRule(type: 'FEE_WAIVER', appliesTo: 'LOAD', value: 50);

    test('W1 100% waiver, min 50000: load 100000 -> fee 0, gst 0, you pay 100000', () {
      expect(bestWaiverPercent([w1], code: 'LOAD', base: 100000), 100);
      final q = cardLoadQuote(amount: 100000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000, offers: [w1]);
      expect(q.fee, 0);
      expect(q.gst, 0);
      expect(q.totalFee, 0);
      expect(q.youPay, 100000);
    });
    test('W1 load 20000 -> not eligible, fee as F2', () {
      expect(bestWaiverPercent([w1], code: 'LOAD', base: 20000), 0);
      final q = cardLoadQuote(amount: 20000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000, offers: [w1]);
      expect(q.totalFee, 590);
      expect(q.youPay, 20590);
    });
    test('W2 50% on load 100000 -> fee 500, gst 90, total 590', () {
      final r = loadFee(100000, waiver: 50);
      expect(r.fee, 500);
      expect(r.gst, 90);
      expect(r.totalFee, 590);
      final q = cardLoadQuote(amount: 100000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000, offers: [w2]);
      expect(q.totalFee, 590);
    });
    test('largest waiver wins; an issue-only waiver does not apply to LOAD', () {
      const issueOnly = CardOfferRule(type: 'FEE_WAIVER', appliesTo: 'ISSUE_PHYSICAL', value: 100);
      expect(bestWaiverPercent([w2, issueOnly, w1], code: 'LOAD', base: 100000), 100);
      expect(bestWaiverPercent([issueOnly], code: 'LOAD', base: 100000), 0);
      expect(bestWaiverPercent([issueOnly], code: 'ISSUE_PHYSICAL'), 100);
      const any = CardOfferRule(type: 'FEE_WAIVER', appliesTo: 'ANY', value: 25);
      expect(bestWaiverPercent([any], code: 'REPLACEMENT'), 25);
    });
  });

  group('C - load cashback', () {
    const c1 = CardOfferRule(type: 'LOAD_CASHBACK', mode: 'PERCENT', value: 2.00, maxCashback: 5000, minAmount: 50000);
    const c2 = CardOfferRule(type: 'LOAD_CASHBACK', mode: 'FLAT', value: 3000);

    test('C1 percent 2, max 5000, min 50000', () {
      expect(cardCashbackFor(c1, 100000), 2000);
      expect(cardCashbackFor(c1, 1000000), 5000);
      expect(cardCashbackFor(c1, 40000), 0);
    });
    test('C2 flat 3000 -> 3000; with C1 live too the largest wins (3000)', () {
      expect(cardCashbackFor(c2, 100000), 3000);
      final best = bestCashbackOffer([c1, c2], 100000);
      expect(best, isNotNull);
      expect(cardCashbackFor(best!, 100000), 3000);
      expect(bestCashbackOffer([c1], 40000), isNull);
    });
    test('cashback does not change what you pay', () {
      final q = cardLoadQuote(amount: 100000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000, offers: [c1]);
      expect(q.cashback, 2000);
      expect(q.youPay, 101180);
    });
  });

  group('E2E arithmetic (offers C1 + W1, load 100000)', () {
    test('you pay 100000, cashback 2000 -> wallet 500000 - 100000 + 2000 = 402000', () {
      const c1 = CardOfferRule(type: 'LOAD_CASHBACK', mode: 'PERCENT', value: 2.00, maxCashback: 5000, minAmount: 50000);
      const w1 = CardOfferRule(type: 'FEE_WAIVER', appliesTo: 'LOAD', value: 100, minAmount: 50000);
      final q = cardLoadQuote(amount: 100000, mode: 'PERCENT', value: 1.00, minFee: 500, maxFee: 5000, offers: [c1, w1]);
      expect(q.youPay, 100000);
      expect(q.cashback, 2000);
      expect(500000 - q.youPay + q.cashback, 402000);
    });
  });
}
