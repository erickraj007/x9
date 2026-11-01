import 'api.dart';

/// `GET /app/kyc` (docs/SIGNUP-KYC-VIP-UPI-V6.md section 2).
class KycInfo {
  const KycInfo({
    this.status = 'NOT_STARTED',
    this.isRequired = true,
    this.remarks = '',
    this.documents = const [],
    this.profile = const {},
  });

  /// NOT_STARTED | SUBMITTED | VERIFIED | REJECTED
  final String status;
  final bool isRequired;
  final String remarks;
  final List<Map<String, dynamic>> documents;

  /// `{aadhaar_masked, pan_masked, bank_masked}`
  final Map<String, dynamic> profile;

  bool get verified => status == 'VERIFIED';
  bool get submitted => status == 'SUBMITTED';

  /// A new submission is allowed.
  bool get canSubmit => status == 'NOT_STARTED' || status == 'REJECTED';

  factory KycInfo.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    final docs = <Map<String, dynamic>>[];
    final rawDocs = m['documents'];
    if (rawDocs is List) {
      for (final d in rawDocs) {
        if (d is Map) docs.add(Map<String, dynamic>.from(d));
      }
    }
    final s = (m['status'] ?? m['kyc_status'] ?? 'NOT_STARTED').toString().toUpperCase();
    return KycInfo(
      status: s.isEmpty ? 'NOT_STARTED' : s,
      isRequired: m['required'] == null ? true : (m['required'] == true || m['required'] == 1),
      remarks: (m['remarks'] ?? '').toString(),
      documents: docs,
      profile: m['profile'] is Map ? Map<String, dynamic>.from(m['profile'] as Map) : const <String, dynamic>{},
    );
  }
}

/// Words for a KYC status ("Not started", "Submitted", "Verified", "Rejected").
String kycStatusLabel(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'SUBMITTED':
      return 'Submitted';
    case 'VERIFIED':
      return 'Verified';
    case 'REJECTED':
      return 'Rejected';
    default:
      return 'Not started';
  }
}

/// True when [e] is the server's `403 KYC_REQUIRED` answer (wallet, prepaid card, banking need a verified KYC).
bool isKycRequired(Object e) => e is ApiException && e.code == 'KYC_REQUIRED';

/// Largest document the server accepts.
const int kycMaxFileBytes = 5 * 1024 * 1024;

class KycApi {
  KycApi._();

  /// `GET /app/kyc`
  static Future<KycInfo> status() async => KycInfo.fromJson(await Api.instance.get('/app/kyc'));

  /// `POST /app/kyc` (multipart). [files] maps the form field (`pan`, `aadhaar_front`, `aadhaar_back`, `photo`,
  /// `cancelled_cheque`) to a local file; [fields] are the text parts (`pan_number`, `aadhaar_number`, bank details).
  static Future<void> submit({required Map<String, ApiFile> files, required Map<String, String> fields}) async {
    await Api.instance.uploadMulti('/app/kyc', files: files, fields: fields);
  }
}
