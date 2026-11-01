import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart' show MediaType;

import 'offline_cache.dart';
import 'server_settings.dart';
import 'session.dart';

/// A local file to upload with [Api.upload].
class ApiFile {
  const ApiFile(this.path, {this.filename});
  final String path;

  /// Name sent to the server (default: the file's own name).
  final String? filename;
}

/// A binary response from [Api.download] (statement exports).
class ApiDownload {
  const ApiDownload(this.bytes, {this.filename, this.contentType});
  final Uint8List bytes;

  /// From the Content-Disposition header, when present.
  final String? filename;
  final String? contentType;
}

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code, this.errors, this.detail});
  final int status;
  final String message;
  final String? code;
  final Map<String, dynamic>? errors;

  /// Technical cause (socket / TLS error text, response excerpt) for support and the startup error screen.
  final String? detail;

  /// [display] plus the technical [detail] when there is one.
  String get full => detail == null || detail!.isEmpty ? display : '$display\n$detail';

  /// Readable text for a snackbar: first validation error, else the server message.
  String get display {
    if (errors != null && errors!.isNotEmpty) {
      final first = errors!.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    // v6.18.1: upload too big for the server (nginx / PHP limit)
    if (status == 413) {
      return 'The files are too large for the X9 server. Take the photos again (smaller) and try again; if it keeps happening tell X9 support (code 413).';
    }
    // v6.14: never show a server stack / SQL / file-path dump to a person - say it plainly (the technical text stays in [detail] / [message]).
    if (status >= 500 || _technical.hasMatch(message)) {
      return 'Something went wrong on our side. Nothing was lost. Please try again in a minute; if it keeps happening, contact support${status >= 500 ? ' (error $status${code == null ? '' : ', $code'})' : ''}.';
    }
    return message;
  }

  static final RegExp _technical = RegExp(r'SQLSTATE|stream or file|Permission denied|Exception|Context:|Stack trace|\.php|/var/www|vendor/');

  @override
  String toString() => display;
}

/// Thin JSON client for the X9 API. All money values are integer paise.
class Api {
  Api._();
  static final Api instance = Api._();

  /// Set by each app ("user" or "merchant").
  String appName = 'user';
  String appVersion = '1.0.1';

  /// Called when the server says the login is no longer valid (401).
  void Function()? onUnauthorized;

  /// Shows the "enter the WhatsApp code" prompt for a transaction (sentTo = masked mobile, length = digits).
  /// Set by X9Bootstrap; returns the code or null when the person cancels.
  Future<String?> Function(String sentTo, int length)? txnOtpPrompt;

  /// Asks for the 4-digit MPIN of a transaction (server answered 422 TXN_MPIN_REQUIRED). Set by X9Bootstrap; null = cancelled.
  Future<String?> Function()? mpinPrompt;

  /// v6.13: asks "Are you sure?" (Cancel / OK) before a change is sent to the server. Set by X9Bootstrap.
  /// Returns true to go ahead. Calls that are already confirmed by a screen call [markConfirmed] first.
  Future<bool> Function(String method, String path)? confirmPrompt;
  DateTime? _confirmedAt;

  /// A Cancel / OK dialog (or review sheet) was just accepted: the next change call needs no second pop-up.
  void markConfirmed() => _confirmedAt = DateTime.now();

  /// Paths that never ask: sign-in / session calls, read receipts, analytics events, device registration,
  /// previews, verification lookups and OTP requests.
  static final RegExp _noConfirm = RegExp(
    r'^/auth/|/(event|events|read|skip|preview|verify|claim|acknowledge|device-token|device-key|location|feedback|otp|heartbeat|ping)(/|$)',
  );

  static bool needsConfirmation(String method, String path) => method != 'GET' && !_noConfirm.hasMatch(path.split('?').first);

  Future<void> _guard(String method, String path) async {
    final ask = confirmPrompt;
    if (ask == null || !needsConfirmation(method, path)) return;
    final t = _confirmedAt;
    _confirmedAt = null; // a confirmation is good for ONE call, for at most 90 seconds
    if (t != null && DateTime.now().difference(t).inSeconds < 90) return;
    if (!await ask(method, path)) throw ApiException(0, 'Cancelled.', code: 'CANCELLED');
  }

  late final http.Client _client = _buildClient();

  http.Client _buildClient() {
    final io = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    // Trust a self-signed certificate ONLY for the X9 server host that is in use at the moment of the call
    // (the Server-settings override is honoured) and only when X9Config.allowSelfSigned is on or the server is
    // addressed by an IPv4 address. See ServerSettings.trustsCertificate.
    io.badCertificateCallback = (X509Certificate cert, String host, int port) => ServerSettings.trustsCertificate(host);
    return IOClient(io);
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    var base = ServerSettings.effectiveApiBase;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    final u = Uri.parse('$base$path');
    return q.isEmpty ? u : u.replace(queryParameters: q);
  }

  Map<String, String> _headers({String? idempotencyKey, String? signature, String? txnOtp}) {
    final s = SessionStore.instance;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-App': appName,
      'X-App-Version': appVersion,
      if (s.deviceId != null) 'X-Device-Id': s.deviceId!,
      if (s.token != null) 'Authorization': 'Bearer ${s.token}',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      if (signature != null) 'X-Txn-Signature': signature,
      if (txnOtp != null) 'X-Txn-Otp': txnOtp,
    };
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) async {
    final c = OfflineCache.instance;
    final uri = _uri(path, query);
    if (!c.enabled || !OfflineCache.cacheable(path) || SessionStore.instance.token == null) {
      return _send(() => _client.get(uri, headers: _headers()));
    }
    // v6.17 offline mode: save every good answer; with no internet, answer from the saved copy.
    c.owner = OfflineCache.ownerOf(SessionStore.instance.token!);
    final key = uri.replace(queryParameters: Map.of(uri.queryParameters)..remove('lat')..remove('lng')).toString();
    try {
      final r = await _send(() => _client.get(uri, headers: _headers()));
      if (c.offline.value) c.offline.value = false;
      unawaited(c.putJson(key, r));
      return r;
    } on ApiException catch (e) {
      if (e.status != 0 && e.code != 'BAD_RESPONSE') rethrow; // a real answer from the server (404, 403...)
      final saved = await c.getJson(key);
      if (saved == null) rethrow;
      c.offline.value = true;
      return saved.value;
    }
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    await _guard('POST', path);
    final amt = (body?['amount'] is num) ? (body!['amount'] as num).toInt() : 0;
    return _withTxnOtp(amt, (otp, mpin) => _send(() => _client.post(_uri(path), headers: _headers(txnOtp: otp), body: jsonEncode(_withMpin(body, mpin)))));
  }

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async {
    await _guard('PUT', path);
    final amt = (body?['amount'] is num) ? (body!['amount'] as num).toInt() : 0;
    return _withTxnOtp(amt, (otp, mpin) => _send(() => _client.put(_uri(path), headers: _headers(txnOtp: otp), body: jsonEncode(_withMpin(body, mpin)))));
  }

  Future<dynamic> delete(String path) async {
    await _guard('DELETE', path);
    return _send(() => _client.delete(_uri(path), headers: _headers()));
  }

  /// Authenticated GET that returns the raw body (file downloads such as statement exports).
  /// Errors are decoded like the JSON calls and thrown as [ApiException].
  Future<ApiDownload> download(String path, [Map<String, dynamic>? query]) async {
    final h = _headers()
      ..['Accept'] = '*/*'
      ..remove('Content-Type');
    http.Response r;
    try {
      r = await _client.get(_uri(path, query), headers: h).timeout(const Duration(seconds: 90));
    } catch (e) {
      if (e is FileSystemException) rethrow; // unreadable upload file: not a network problem
      throw _networkError(e);
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return ApiDownload(
        r.bodyBytes,
        filename: _dispositionFilename(r.headers['content-disposition']),
        contentType: r.headers['content-type'],
      );
    }
    if (r.statusCode == 401) onUnauthorized?.call();
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      json = null;
    }
    final m = json is Map ? json : const {};
    throw ApiException(
      r.statusCode,
      (m['message'] ?? 'Request failed (${r.statusCode})').toString(),
      code: m['code']?.toString(),
      errors: m['errors'] is Map ? Map<String, dynamic>.from(m['errors'] as Map) : null,
    );
  }

  /// `attachment; filename="x9-sales-2026-10-01_2026-10-13.xlsx"` -> the file name (null when absent).
  static String? _dispositionFilename(String? header) {
    if (header == null || header.isEmpty) return null;
    final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false).firstMatch(header);
    if (star != null) {
      try {
        final v = Uri.decodeComponent(star.group(1)!.trim());
        if (v.isNotEmpty) return v;
      } catch (_) {}
    }
    final quoted = RegExp(r'filename\s*=\s*"([^"]+)"', caseSensitive: false).firstMatch(header);
    if (quoted != null) return quoted.group(1);
    final plain = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(header);
    return plain?.group(1)?.trim();
  }

  /// multipart/form-data upload (POST). Each file goes in the form field [field] (e.g. `images[]`);
  /// [fields] are extra text parts. Only png / jpeg / webp get a proper content type, others are sent as octet-stream.
  Future<dynamic> upload(String path, {required String field, required List<ApiFile> files, Map<String, String>? fields}) async {
    await _guard('POST', path);
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path));
      final h = _headers()..remove('Content-Type'); // the multipart boundary sets its own content type
      req.headers.addAll(h);
      if (fields != null) req.fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(field, f.path, filename: f.filename, contentType: _imageType(f.filename ?? f.path)));
      }
      final streamed = await _client.send(req);
      return http.Response.fromStream(streamed);
    });
  }

  /// multipart/form-data upload (POST) where each file has its own form field name (KYC documents).
  /// [files] maps the field name to the local file; [fields] are extra text parts.
  Future<dynamic> uploadMulti(String path, {required Map<String, ApiFile> files, Map<String, String>? fields}) async {
    await _guard('POST', path);
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path));
      final h = _headers()..remove('Content-Type'); // the multipart boundary sets its own content type
      req.headers.addAll(h);
      if (fields != null) req.fields.addAll(fields);
      for (final e in files.entries) {
        final f = e.value;
        req.files.add(await http.MultipartFile.fromPath(e.key, f.path, filename: f.filename, contentType: _imageType(f.filename ?? f.path)));
      }
      final streamed = await _client.send(req);
      return http.Response.fromStream(streamed);
    });
  }

  static MediaType _imageType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (n.endsWith('.png')) return MediaType('image', 'png');
    if (n.endsWith('.webp')) return MediaType('image', 'webp');
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return MediaType('image', 'jpeg');
    return MediaType('application', 'octet-stream');
  }

  /// Money-moving call. The caller must have unlocked the phone first (AppLock.confirm).
  /// Adds Idempotency-Key and the device approval signature for [amount] (paise; 0 when none).
  Future<dynamic> money(String method, String path, Map<String, dynamic> body, {required int amount, String? idempotencyKey}) async {
    await _guard(method, path);
    final key = idempotencyKey ?? SessionStore.newIdempotencyKey();
    final sig = await SessionStore.instance.signTxn(key, amount);
    Future<dynamic> go(String? otp, String? mpin) {
      final h = _headers(idempotencyKey: key, signature: sig, txnOtp: otp);
      final payload = jsonEncode(_withMpin(body, mpin));
      final uri = _uri(path);
      return _send(() => method == 'PUT'
          ? _client.put(uri, headers: h, body: payload)
          : method == 'GET'
              ? _client.get(_uri(path, body), headers: h)
              : _client.post(uri, headers: h, body: payload));
    }

    return _withTxnOtp(amount, go);
  }

  static Map<String, dynamic> _withMpin(Map<String, dynamic>? body, String? mpin) =>
      {...?body, if (mpin != null && mpin.isNotEmpty) 'mpin': mpin};

  /// v6.2: a transaction is approved with the MPIN AND a WhatsApp code. The server answers 422 TXN_MPIN_REQUIRED, then
  /// 428 TXN_OTP_REQUIRED; for each we ask the person (MPIN pad, then the code we send with POST /auth/txn-otp) and repeat
  /// the SAME call (same Idempotency-Key) with `mpin` in the body and X-Txn-Otp in the header.
  Future<dynamic> _withTxnOtp(int amount, Future<dynamic> Function(String? otp, String? mpin) go) async {
    String? otp;
    String? mpin;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await go(otp, mpin);
      } on ApiException catch (e) {
        if (e.code == 'TXN_MPIN_REQUIRED' && mpinPrompt != null) {
          mpin = await mpinPrompt!();
          if (mpin == null) throw ApiException(422, 'Transaction not confirmed.', code: 'TXN_CANCELLED');
          continue;
        }
        if (e.code == 'TXN_OTP_REQUIRED' && txnOtpPrompt != null) {
          final sent = await post('/auth/txn-otp', {'amount': amount});
          final m = sent is Map ? sent : const {};
          otp = await txnOtpPrompt!('${m['sent_to'] ?? ''}', (m['length'] as num?)?.toInt() ?? 6);
          if (otp == null) throw ApiException(428, 'Transaction not confirmed.', code: 'TXN_OTP_CANCELLED');
          continue;
        }
        rethrow;
      }
    }
    return go(otp, mpin);
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response r;
    try {
      r = await call().timeout(const Duration(seconds: 40));
    } catch (e) {
      if (e is FileSystemException) rethrow; // unreadable upload file: not a network problem
      throw _networkError(e);
    }
    dynamic json;
    var notJson = false;
    if (r.bodyBytes.isNotEmpty) {
      try {
        json = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      } catch (_) {
        json = null; // HTML / plain text from a proxy or the wrong server
        notJson = r.body.trim().isNotEmpty;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (notJson) {
        // A 2xx page that is not JSON means this is not the X9 API (captive portal, proxy, wrong address).
        throw ApiException(
          r.statusCode,
          'X9 is not reachable right now. Please try again in a moment.',
          code: 'BAD_RESPONSE',
          detail: 'GET/POST ${r.request?.url} -> HTTP ${r.statusCode}, ${_excerpt(r.body)}',
        );
      }
      return json;
    }
    if (r.statusCode == 401) onUnauthorized?.call();
    final m = json is Map ? json : const {};
    throw ApiException(
      r.statusCode,
      (m['message'] ?? 'Request failed (${r.statusCode})').toString(),
      code: m['code']?.toString(),
      errors: m['errors'] is Map ? Map<String, dynamic>.from(m['errors'] as Map) : null,
      detail: json is Map ? null : 'HTTP ${r.statusCode} ${r.request?.url ?? ''} ${_excerpt(r.body)}',
    );
  }

  /// Turns a low-level failure (socket, TLS, timeout, bad response) into an [ApiException] a person can read,
  /// with the technical cause in [ApiException.detail].
  static ApiException _networkError(Object e) {
    if (e is ApiException) return e;
    final host = ServerSettings.effectiveHost;
    if (e is TlsException) {
      return ApiException(0, 'Secure connection to X9 failed. Please try again.',
          code: 'TLS', detail: 'TLS error talking to $host: ${e.message}${_os(e.osError)}');
    }
    if (e is SocketException) {
      return ApiException(0, 'No internet connection. Check your network and try again.',
          code: 'OFFLINE', detail: 'Cannot reach $host: ${e.message}${_os(e.osError)}');
    }
    if (e is TimeoutException) {
      return ApiException(0, 'X9 is taking too long to answer. Try again.', code: 'TIMEOUT', detail: 'Timed out talking to $host');
    }
    if (e is http.ClientException || e is HttpException) {
      return ApiException(0, 'Could not reach X9. Check your internet connection and try again.',
          code: 'OFFLINE', detail: '$e');
    }
    if (e is FormatException) {
      return ApiException(0, 'X9 is not reachable right now. Please try again in a moment.', code: 'BAD_ADDRESS', detail: '$e');
    }
    return ApiException(0, 'Something went wrong while contacting X9. Try again.', code: 'NETWORK', detail: '$e');
  }

  static String _os(OSError? e) => e == null || e.message.isEmpty ? '' : ' (${e.message})';

  static String _excerpt(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 160 ? '${t.substring(0, 160)}...' : t;
  }
}
