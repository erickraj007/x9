import 'api.dart';

/// Who is signing up. The wire value is what `/auth/signup/*` expects in `role`.
enum SignupRole { user, merchant }

extension SignupRoleWire on SignupRole {
  String get wire => this == SignupRole.merchant ? 'MERCHANT' : 'USER';
}

int _asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? fallback;
}

/// Answer of `POST /auth/signup/request`: `{sent, channel, length, mode, resend_in}`.
class SignupOtpInfo {
  const SignupOtpInfo({this.sent = true, this.channel = 'WHATSAPP', this.length = 6, this.mode = 'whatsapp', this.resendIn = 30});

  final bool sent;
  final String channel;

  /// Number of digits in the code (6 for WhatsApp, 5 or 6 in the fixed demo mode).
  final int length;

  /// "whatsapp" (real code) or "fixed" (demo codes).
  final String mode;

  /// Seconds before another code may be requested.
  final int resendIn;

  factory SignupOtpInfo.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    final len = _asInt(m['length'], 6);
    final resend = _asInt(m['resend_in'], 30);
    return SignupOtpInfo(
      sent: m['sent'] == null ? true : (m['sent'] == true || m['sent'] == 1),
      channel: (m['channel'] ?? 'WHATSAPP').toString(),
      length: len >= 4 && len <= 8 ? len : 6,
      mode: (m['mode'] ?? 'whatsapp').toString(),
      resendIn: resend > 0 ? resend : 30,
    );
  }
}

/// Readable text for sign-up errors (MOBILE_TAKEN, OTP_INVALID, OTP_LOCKED, else the server message).
String signupErrorMessage(Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'MOBILE_TAKEN':
        return 'This number already has an account. Sign in instead.';
      case 'OTP_INVALID':
        return 'That code is not correct. Check the WhatsApp message and try again.';
      case 'OTP_LOCKED':
        return 'Too many wrong codes. Wait a few minutes, then ask for a new code.';
      case 'OTP_EXPIRED':
        return 'That code has expired. Ask for a new code.';
      case 'THROTTLED':
      case 'TOO_MANY_REQUESTS':
        return 'Please wait a little before asking for another code.';
    }
    if (e.status == 429) return 'Please wait a little before asking for another code.';
    return e.display;
  }
  final t = e.toString();
  return t.startsWith('Exception: ') ? t.substring(11) : t;
}

/// Self sign-up (docs/SIGNUP-KYC-VIP-UPI-V6.md section 1). No sign-in is needed for these calls.
class SignupApi {
  SignupApi._();

  /// `POST /auth/signup/request` - sends a code to the number's WhatsApp.
  /// Throws [ApiException] `MOBILE_TAKEN` (409) when the number already has an account.
  static Future<SignupOtpInfo> requestOtp(String mobile, SignupRole role) async {
    final r = await Api.instance.post('/auth/signup/request', {'mobile': mobile, 'role': role.wire});
    return SignupOtpInfo.fromJson(r);
  }

  /// `POST /auth/signup/verify` - [fields] is the full body (role, otp, name, mobile, e-mail, address, pincode, lat, lng, ...).
  /// Returns the same map as `/auth/otp/verify` (`token`, `user`, `signup: true`).
  static Future<Map<String, dynamic>> verify(Map<String, dynamic> fields) async {
    final r = await Api.instance.post('/auth/signup/verify', fields);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }
}
