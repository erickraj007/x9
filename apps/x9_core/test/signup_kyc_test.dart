import 'package:flutter_test/flutter_test.dart';
import 'package:x9_core/src/api.dart';
import 'package:x9_core/src/kyc_api.dart';
import 'package:x9_core/src/signup_api.dart';
import 'package:x9_core/src/signup_validators.dart';

void main() {
  group('SignupValidators', () {
    test('mobile accepts 10 digits and +91 / 0 prefixes', () {
      expect(SignupValidators.mobile('9876543210'), '9876543210');
      expect(SignupValidators.mobile('+91 98765 43210'), '9876543210');
      expect(SignupValidators.mobile('09876543210'), '9876543210');
      expect(SignupValidators.mobile('1234567890'), isNull);
      expect(SignupValidators.mobile('98765'), isNull);
    });
    test('email', () {
      expect(SignupValidators.email(' a@b.co '), 'a@b.co');
      expect(SignupValidators.email('a@b'), isNull);
      expect(SignupValidators.email(''), isNull);
    });
    test('pincode is 6 digits not starting with 0', () {
      expect(SignupValidators.pincode('600001'), '600001');
      expect(SignupValidators.pincode('012345'), isNull);
      expect(SignupValidators.pincode('60001'), isNull);
      expect(SignupValidators.pincode('6000011'), isNull);
    });
    test('aadhaar, pan, ifsc, bank account', () {
      expect(SignupValidators.aadhaar('1234 5678 9012'), '123456789012');
      expect(SignupValidators.aadhaar('12345'), isNull);
      expect(SignupValidators.pan('abcde1234f'), 'ABCDE1234F');
      expect(SignupValidators.pan('ABCD1234F'), isNull);
      expect(SignupValidators.ifsc('hdfc0001234'), 'HDFC0001234');
      expect(SignupValidators.ifsc('HDFC1001234'), isNull);
      expect(SignupValidators.bankAccount('123456789'), '123456789');
      expect(SignupValidators.bankAccount('1234'), isNull);
    });
    test('password and name', () {
      expect(SignupValidators.passwordOk('12345678'), isTrue);
      expect(SignupValidators.passwordOk('1234567'), isFalse);
      expect(SignupValidators.nameOk(' A '), isFalse);
      expect(SignupValidators.nameOk('Ravi'), isTrue);
    });
    test('display', () {
      expect(SignupValidators.display('9876543210'), '+91 98765 43210');
    });
  });

  group('SignupApi parsing', () {
    test('role wire values', () {
      expect(SignupRole.user.wire, 'USER');
      expect(SignupRole.merchant.wire, 'MERCHANT');
    });
    test('SignupOtpInfo.fromJson', () {
      final i = SignupOtpInfo.fromJson({'sent': true, 'channel': 'WHATSAPP', 'length': 6, 'mode': 'whatsapp', 'resend_in': 45});
      expect(i.length, 6);
      expect(i.resendIn, 45);
      expect(i.mode, 'whatsapp');
      final d = SignupOtpInfo.fromJson(null);
      expect(d.length, 6);
      expect(d.resendIn, 30);
      expect(SignupOtpInfo.fromJson({'length': '5', 'resend_in': '20'}).length, 5);
    });
    test('error messages', () {
      expect(signupErrorMessage(ApiException(409, 'x', code: 'MOBILE_TAKEN')), 'This number already has an account. Sign in instead.');
      expect(signupErrorMessage(ApiException(422, 'x', code: 'OTP_INVALID')), contains('not correct'));
      expect(signupErrorMessage(ApiException(423, 'x', code: 'OTP_LOCKED')), contains('Too many'));
      expect(signupErrorMessage(ApiException(500, 'Boom')), 'Boom');
      expect(signupErrorMessage(Exception('Location is off')), 'Location is off');
    });
  });

  group('KYC parsing', () {
    test('KycInfo.fromJson', () {
      final k = KycInfo.fromJson({
        'status': 'rejected',
        'required': true,
        'remarks': 'Blurry PAN',
        'documents': [
          {'type': 'PAN'}
        ],
        'profile': {'pan_masked': 'ABCDE****F'},
      });
      expect(k.status, 'REJECTED');
      expect(k.canSubmit, isTrue);
      expect(k.verified, isFalse);
      expect(k.remarks, 'Blurry PAN');
      expect(k.documents.length, 1);
      expect(k.profile['pan_masked'], 'ABCDE****F');
    });
    test('defaults and labels', () {
      final k = KycInfo.fromJson(null);
      expect(k.status, 'NOT_STARTED');
      expect(k.canSubmit, isTrue);
      expect(KycInfo.fromJson({'status': 'VERIFIED'}).canSubmit, isFalse);
      expect(kycStatusLabel('SUBMITTED'), 'Submitted');
      expect(kycStatusLabel(null), 'Not started');
    });
    test('isKycRequired', () {
      expect(isKycRequired(ApiException(403, 'KYC', code: 'KYC_REQUIRED')), isTrue);
      expect(isKycRequired(ApiException(403, 'No', code: 'OTHER')), isFalse);
      expect(isKycRequired(Exception('x')), isFalse);
    });
  });
}
