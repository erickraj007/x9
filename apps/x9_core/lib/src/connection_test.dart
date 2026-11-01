import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'server_settings.dart';

/// Outcome of one request made by [ServerConnectionTest].
class ProbeResult {
  ProbeResult(this.label, this.url);
  final String label;
  final String url;

  int? status;
  int latencyMs = 0;

  /// Network / TLS failure text (null when an HTTP answer was received).
  String? error;

  /// Set when the certificate failed normal validation: what it looked like and whether the app trusts it.
  String? tls;

  /// First characters of the body (to spot an HTML page from a proxy).
  String? snippet;

  bool get ok => status != null && status! >= 200 && status! < 300;

  String get summary {
    final b = StringBuffer(ok ? 'OK' : (status != null ? 'HTTP $status' : 'FAILED'));
    b.write('  $label  ${latencyMs}ms');
    if (error != null) b.write('\n    $error');
    if (tls != null) b.write('\n    TLS: $tls');
    if (status != null && !ok && snippet != null && snippet!.isNotEmpty) b.write('\n    body: $snippet');
    return b.toString();
  }
}

/// Calls the server's health endpoints with the same TLS trust rule the app uses:
///  * `{host}/up`            the Laravel health check at the host root (Caddy forwards /up)
///  * `{base}/health`        an API-level health route, when the backend has one
///  * `{base}/categories`    a public API route, proves the /api/v1 path is right
/// and reports HTTP status, latency, TLS problems and the start of the body for each.
class ServerConnectionTest {
  ServerConnectionTest._();

  static Future<List<ProbeResult>> run(String base, {Duration timeout = const Duration(seconds: 8)}) async {
    final u = Uri.tryParse(base);
    if (u == null || u.host.isEmpty) {
      return [ProbeResult('address', base)..error = 'Not a valid address'];
    }
    final origin = Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null).toString();
    final probes = <ProbeResult>[
      ProbeResult('/up', '$origin/up'),
      ProbeResult('/health', '$base/health'),
      ProbeResult('/categories', '$base/categories'),
    ];
    await Future.wait(probes.map((p) => _probe(p, base, timeout)));
    return probes;
  }

  static Future<void> _probe(ProbeResult p, String base, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final trusted = ServerSettings.trustsCertificate(host, serverBase: base);
      p.tls = 'certificate not trusted by Android (${_certInfo(cert)}); '
          '${trusted ? 'accepted by the app (self-signed server allowed)' : 'REJECTED by the app'}';
      return trusted;
    };
    final sw = Stopwatch()..start();
    try {
      final req = await client.getUrl(Uri.parse(p.url)).timeout(timeout);
      req.headers.set('Accept', 'application/json');
      final res = await req.close().timeout(timeout);
      p.status = res.statusCode;
      final bytes = <int>[];
      try {
        await for (final chunk in res.timeout(timeout)) {
          bytes.addAll(chunk);
          if (bytes.length > 1024) break;
        }
      } catch (_) {}
      p.snippet = utf8.decode(bytes, allowMalformed: true).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (p.snippet!.length > 120) p.snippet = p.snippet!.substring(0, 120);
    } on TlsException catch (e) {
      p.error = 'TLS error: ${e.message}${_os(e.osError)}';
    } on SocketException catch (e) {
      p.error = 'Cannot connect: ${e.message}${_os(e.osError)}';
    } on TimeoutException {
      p.error = 'No answer within ${timeout.inSeconds}s';
    } on HttpException catch (e) {
      p.error = 'HTTP error: ${e.message}';
    } catch (e) {
      p.error = '$e';
    } finally {
      sw.stop();
      p.latencyMs = sw.elapsedMilliseconds;
      client.close(force: true);
    }
  }

  static String _os(OSError? e) => e == null || e.message.isEmpty ? '' : ' (${e.message})';

  static String _certInfo(X509Certificate c) {
    try {
      return 'subject ${c.subject}, issuer ${c.issuer}, valid ${c.startValidity.toIso8601String().substring(0, 10)} to ${c.endValidity.toIso8601String().substring(0, 10)}';
    } catch (_) {
      return 'details unavailable';
    }
  }

  /// One line for the person: what the results mean.
  static String verdict(List<ProbeResult> r) {
    if (r.isEmpty) return 'No result';
    if (r.any((p) => p.label == '/categories' && p.ok)) return 'Connected: the X9 API answers at this address.';
    if (r.any((p) => p.ok)) return 'The server answers, but the API path may be wrong. The address must end with /api/v1.';
    final answered = r.where((p) => p.status != null).toList();
    if (answered.isNotEmpty) {
      return 'A server answered (HTTP ${answered.first.status}) but it is not the X9 API. Check the address and that the server is running.';
    }
    final tls = r.any((p) => (p.error ?? '').startsWith('TLS error'));
    if (tls) return 'Secure connection failed. The server certificate is not accepted (self-signed or wrong host name).';
    return 'Cannot reach the server. Check the phone internet connection and the address.';
  }
}
