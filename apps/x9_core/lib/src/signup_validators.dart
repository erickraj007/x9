/// Pure validation helpers for the sign-up and KYC forms (no Flutter imports, easy to unit test).
/// Every method returns the cleaned value, or null when the text is not valid.
class SignupValidators {
  SignupValidators._();

  /// 10-digit Indian mobile from what a person typed ("+91 98765 43210", "09876543210"), or null.
  static String? mobile(String text) {
    var s = text.replaceAll(RegExp(r'\D'), '');
    if (s.length == 12 && s.startsWith('91')) s = s.substring(2);
    if (s.length == 11 && s.startsWith('0')) s = s.substring(1);
    return RegExp(r'^[6-9]\d{9}$').hasMatch(s) ? s : null;
  }

  static String? email(String text) {
    final t = text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? t : null;
  }

  /// 6-digit Indian pin code (first digit 1-9).
  static String? pincode(String text) {
    final t = text.trim();
    return RegExp(r'^[1-9]\d{5}$').hasMatch(t) ? t : null;
  }

  /// 12-digit Aadhaar number; spaces are ignored.
  static String? aadhaar(String text) {
    final t = text.replaceAll(RegExp(r'\s'), '');
    return RegExp(r'^\d{12}$').hasMatch(t) ? t : null;
  }

  /// PAN such as ABCDE1234F (upper-cased).
  static String? pan(String text) {
    final t = text.trim().toUpperCase();
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(t) ? t : null;
  }

  /// IFSC such as HDFC0001234 (upper-cased).
  static String? ifsc(String text) {
    final t = text.trim().toUpperCase();
    return RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(t) ? t : null;
  }

  /// Bank account number, 9 to 18 digits.
  static String? bankAccount(String text) {
    final t = text.replaceAll(RegExp(r'\s'), '');
    return RegExp(r'^\d{9,18}$').hasMatch(t) ? t : null;
  }

  static bool passwordOk(String text) => text.length >= 8;

  /// "Name" must have at least 2 visible characters.
  static bool nameOk(String text) => text.trim().length >= 2;

  /// "+91 98765 43210" style text for the OTP step (falls back to the input).
  static String display(String mobile10) {
    if (mobile10.length != 10) return '+91 $mobile10';
    return '+91 ${mobile10.substring(0, 5)} ${mobile10.substring(5)}';
  }
}
