import 'package:flutter_test/flutter_test.dart';
import 'package:x9_user/screens/vip/vip_models.dart';
import 'package:x9_user/util/data_uri.dart';

void main() {
  group('decodeImageDataUri', () {
    test('decodes a base64 png data URI', () {
      final b = decodeImageDataUri('data:image/png;base64,iVBORw0KGgo=');
      expect(b, isNotNull);
      expect(b!.length, 8);
    });
    test('returns null for svg, non-image, broken or empty input', () {
      expect(decodeImageDataUri('data:image/svg+xml;base64,PHN2Zz48L3N2Zz4='), isNull);
      expect(decodeImageDataUri('upi://pay?pa=a@b'), isNull);
      expect(decodeImageDataUri('data:image/png;base64,@@@'), isNull);
      expect(decodeImageDataUri(''), isNull);
      expect(decodeImageDataUri(null), isNull);
    });
  });

  group('VipStatus', () {
    test('parses plans, benefits and purchase', () {
      final s = VipStatus.fromJson({
        'is_vip': false,
        'kyc_status': 'VERIFIED',
        'plans': [
          {'id': 3, 'name': 'Gold', 'price': 49900, 'description': 'd', 'benefits': ['A', 'B']}
        ],
        'purchase': {'purchase_id': 'VIP1', 'status': 'PENDING'},
      });
      expect(s.isVip, isFalse);
      expect(s.kycVerified, isTrue);
      expect(s.plans.single.price, 49900);
      expect(s.plans.single.benefits, ['A', 'B']);
      expect(s.purchase!['purchase_id'], 'VIP1');
    });
    test('handles missing data', () {
      final s = VipStatus.fromJson(null);
      expect(s.plans, isEmpty);
      expect(s.purchase, isNull);
      expect(s.isVip, isFalse);
    });
  });

  group('purchase helpers', () {
    test('status', () {
      expect(vipIsPaid('PAID'), isTrue);
      expect(vipIsDead('EXPIRED'), isTrue);
      expect(vipIsPaid('PENDING'), isFalse);
      expect(vipPurchaseStatus({'status': 'paid'}), 'PAID');
    });
    test('fulfilment label', () {
      expect(vipFulfilmentLabel('CARD_PENDING'), 'Collect your physical card');
      expect(vipFulfilmentLabel('DISPATCHED'), contains('dispatched'));
    });
    test('expiry', () {
      final now = DateTime.utc(2026, 10, 16, 12);
      expect(vipExpired('2026-10-16T11:00:00Z', now: now), isTrue);
      expect(vipExpired('2026-10-16T13:00:00Z', now: now), isFalse);
      expect(vipExpired('', now: now), isFalse);
      expect(vipExpired('garbage', now: now), isFalse);
    });
  });
}
