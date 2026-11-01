import 'config.dart';
import 'session.dart';
import 'startup_log.dart';

/// Runtime server-address override, kept in the secure store (survives sign-out and app restarts).
///
/// The APK has an address compiled in ([X9Config.apiBase]); when that one is wrong or unreachable the person
/// (or support) can type the right one in Server settings without a new build. The override is read by
/// [Api] at call time.
class ServerSettings {
  ServerSettings._();

  static const _key = 'server_override';

  static String? _override;

  /// The saved override (normalised), or null when the compiled-in address is used.
  static String? get override => _override;

  static bool get hasOverride => _override != null;

  /// What requests use: the override when saved, else the compiled-in default.
  static String get effectiveApiBase => _override ?? X9Config.defaultApiBase;

  /// Host name of [effectiveApiBase] ('' when unparsable).
  static String get effectiveHost => Uri.tryParse(effectiveApiBase)?.host ?? '';

  /// Reads the saved override. Never throws; an unreadable or invalid stored value is ignored.
  static Future<void> load() async {
    try {
      final v = await SessionStore.instance.read(_key);
      if (v == null || v.trim().isEmpty) {
        _override = null;
        return;
      }
      final r = normalize(v);
      _override = r.value; // null when the stored text is no longer valid
      if (r.value == null) StartupLog.add('Ignored invalid saved server address "$v": ${r.error}');
    } catch (e) {
      _override = null;
      StartupLog.add('Could not read the saved server address: $e');
    }
  }

  /// Validates and stores [input]. Returns the normalised address; throws [FormatException] with a readable
  /// message when the input is not acceptable.
  static Future<String> save(String input) async {
    final r = normalize(input);
    final v = r.value;
    if (v == null) throw FormatException(r.error ?? 'Invalid server address');
    _override = v;
    await SessionStore.instance.write(_key, v);
    StartupLog.add('Server address saved: $v');
    return v;
  }

  /// Removes the override: the compiled-in address is used again.
  static Future<void> reset() async {
    _override = null;
    try {
      await SessionStore.instance.write(_key, null);
    } catch (e) {
      StartupLog.add('Could not clear the saved server address: $e');
    }
    StartupLog.add('Server address reset to default: ${X9Config.defaultApiBase}');
  }

  /// null when [input] is acceptable, else the reason (for a form validator).
  static String? validate(String input) => normalize(input).error;

  // ---------------------------------------------------------------------------------------------------------
  // Normalisation
  // ---------------------------------------------------------------------------------------------------------

  /// Turns what the person typed into the canonical form `scheme://host[:port]/api/v1`.
  ///
  /// * a missing scheme is taken as https
  /// * only the host (or host + `/api`) typed -> `/api/v1` is added; trailing `/` removed; host lower-cased
  /// * https is required, http only for localhost and plain IPv4 addresses (a server reached by IP, before it has a domain + HTTPS)
  /// * the path must end with `/api/v1`; no query / fragment / credentials
  static ({String? value, String? error}) normalize(String input) {
    var t = input.trim();
    if (t.isEmpty) return (value: null, error: 'Enter the server address, e.g. https://api.example.com');
    if (RegExp(r'\s').hasMatch(t)) return (value: null, error: 'The address must not contain spaces');
    if (!t.contains('://')) {
      if (t.startsWith('//')) t = t.substring(2);
      t = 'https://$t';
    }
    final u = Uri.tryParse(t);
    if (u == null) return (value: null, error: 'This is not a valid web address');
    final scheme = u.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return (value: null, error: 'The address must start with https://');
    final host = u.host.toLowerCase();
    if (host.isEmpty) return (value: null, error: 'The address has no host name');
    if (u.userInfo.isNotEmpty) return (value: null, error: 'Do not put a user name or password in the address');
    if (u.hasQuery || u.hasFragment) return (value: null, error: 'Remove everything after "?" or "#" from the address');
    if (u.hasPort && (u.port <= 0 || u.port > 65535)) return (value: null, error: 'The port number is not valid');
    if (scheme == 'http' && !_isPrivateTestHost(host)) {
      return (value: null, error: 'Use https://. Plain http:// is only allowed for localhost and a numeric IP address such as http://203.0.113.10');
    }
    var path = u.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final lower = path.toLowerCase();
    if (lower.isEmpty) {
      path = '/api/v1';
    } else if (lower.endsWith('/api')) {
      path = '$path/v1';
    } else if (!lower.endsWith('/api/v1')) {
      return (value: null, error: 'The address must end with /api/v1 (or give only the host and it is added for you)');
    }
    final hostText = host.contains(':') ? '[$host]' : host; // IPv6 literal
    final port = u.hasPort && !((scheme == 'https' && u.port == 443) || (scheme == 'http' && u.port == 80)) ? ':${u.port}' : '';
    return (value: '$scheme://$hostText$port$path', error: null);
  }

  /// Compiled-in address -> clean form. Lenient on purpose (a build-time choice is not blocked by the
  /// https rule); EMPTY -> [X9Config.fallbackApiBase].
  static String cleanDefault(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return X9Config.fallbackApiBase;
    final n = normalize(t);
    if (n.value != null) return n.value!;
    var s = t;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final u = Uri.tryParse(s);
    return u != null && u.scheme.isNotEmpty && u.host.isNotEmpty ? s : X9Config.fallbackApiBase;
  }

  static bool _isPrivateTestHost(String host) {
    if (host == 'localhost') return true;
    final p = _ipv4Parts(host);
    if (p == null) return false;
    return true; // any valid IPv4 literal (server reached by IP address)
  }

  static List<int>? _ipv4Parts(String host) {
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (m == null) return null;
    final p = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
    return p.any((n) => n > 255) ? null : p;
  }

  /// True when [host] is a dotted IPv4 address.
  static bool isIpv4(String host) => _ipv4Parts(host) != null;

  // ---------------------------------------------------------------------------------------------------------
  // TLS trust policy (used by Api, the KYC document fetch and the connection test)
  // ---------------------------------------------------------------------------------------------------------

  /// Whether a certificate that failed normal validation is accepted for [host]. Only the configured X9 server
  /// host ([serverBase], default [effectiveApiBase]) qualifies, and only when ALLOW_SELF_SIGNED is on or the
  /// server is addressed by an IPv4 address (no public certificate can exist for a bare IP).
  static bool trustsCertificate(String host, {String? serverBase}) {
    final apiHost = (Uri.tryParse(serverBase ?? effectiveApiBase)?.host ?? '').toLowerCase();
    if (apiHost.isEmpty || host.toLowerCase() != apiHost) return false;
    return X9Config.allowSelfSigned || isIpv4(apiHost);
  }
}
