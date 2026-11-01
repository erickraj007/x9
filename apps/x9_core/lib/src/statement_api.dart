import 'dart:typed_data';

import 'api.dart';
import 'statement_models.dart';

/// Which route group a statement comes from.
class StatementScope {
  const StatementScope._(this.base);

  /// Path prefix under /api/v1.
  final String base;

  /// `/merchant/statements/{sales|settlements}`
  static const merchant = StatementScope._('/merchant/statements');

  /// `/app/statements/{purchases|payments|card|bank-transfers}`
  static const user = StatementScope._('/app/statements');

  /// `/admin/statements/{transactions|invoices|settlements|card-ops}` (perm reports.view)
  static const admin = StatementScope._('/admin/statements');
}

/// A downloaded export, ready to be saved.
class StatementFile {
  const StatementFile(this.bytes, this.filename, this.contentType);
  final Uint8List bytes;
  final String filename;
  final String contentType;
}

/// v5 statements (docs/HISTORY-EXPORT-V5.md): paged list + export download. Errors surface as [ApiException]
/// (e.g. code INVALID_PERIOD, EXPORT_TOO_LARGE).
class StatementApi {
  StatementApi._();

  /// Export formats the server supports.
  static const formats = ['xlsx', 'pdf', 'txt', 'csv'];

  /// `GET {scope}/{key}` with the period / filter params.
  static Future<StatementData> list(StatementScope scope, String key, StatementQuery query, {int page = 1, int perPage = 25}) async {
    final params = <String, dynamic>{...query.toParams(), 'page': page, 'per_page': perPage};
    return StatementData.fromJson(await Api.instance.get('${scope.base}/$key', params));
  }

  /// `GET {scope}/{key}/export?format=` - all rows, same filters as the list (no paging).
  static Future<StatementFile> export(StatementScope scope, String key, StatementQuery query, String format) async {
    final params = <String, dynamic>{...query.toParams(), 'format': format};
    final d = await Api.instance.download('${scope.base}/$key/export', params);
    final from = query.from ?? '';
    final fallback = 'x9-$key-${from.isEmpty ? query.period : from}.$format';
    return StatementFile(d.bytes, d.filename ?? fallback, d.contentType ?? '');
  }
}
