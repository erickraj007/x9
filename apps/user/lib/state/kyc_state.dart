import 'package:flutter/foundation.dart';
import 'package:x9_core/x9_core.dart';

/// KYC status for the home banner and menus. `GET /app/profile` may not carry `kyc_status`, so it is read lazily
/// from `GET /app/kyc` and cached for the current login.
class KycState extends ChangeNotifier {
  KycState._();
  static final KycState instance = KycState._();

  String? _status;
  String _remarks = '';
  String? _token;
  bool _loaded = false;
  bool _loading = false;

  bool get _current => _token != null && _token == SessionStore.instance.token;

  /// NOT_STARTED / SUBMITTED / VERIFIED / REJECTED, or null while unknown.
  String? get status {
    if (_current && _status != null) return _status;
    final fromProfile = SessionStore.instance.user?['kyc_status'];
    final s = fromProfile == null ? '' : fromProfile.toString().toUpperCase();
    return s.isEmpty ? null : s;
  }

  String get remarks => _current ? _remarks : '';

  bool get needsKyc {
    final s = status;
    return s != null && s != 'VERIFIED';
  }

  String get label => status == null ? 'Check status' : kycStatusLabel(status);

  /// Reads the status once per login (or again when [force]). Never throws.
  Future<void> load({bool force = false}) async {
    final tok = SessionStore.instance.token;
    if (tok == null || tok.isEmpty) return;
    if (_token != tok) {
      _token = tok;
      _status = null;
      _remarks = '';
      _loaded = false;
    }
    if (_loading || (_loaded && !force)) return;
    _loading = true;
    try {
      setInfo(await KycApi.status());
    } catch (_) {
      // keep the previous value; the banner simply stays hidden when unknown
    } finally {
      _loading = false;
    }
  }

  void setInfo(KycInfo info) {
    final tok = SessionStore.instance.token;
    if (tok == null || tok.isEmpty) return;
    _token = tok;
    _status = info.status;
    _remarks = info.remarks;
    _loaded = true;
    notifyListeners();
  }
}
