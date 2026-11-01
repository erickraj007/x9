import 'server_settings.dart';

/// Build-time configuration. Set with --dart-define when building the APK, e.g.
///   flutter build apk --dart-define=API_BASE=http://187.127.157.39/api/v1
///
/// The compiled-in address can be overridden on the phone (Server settings screen, see [ServerSettings]);
/// code that makes requests must use [effectiveApiBase] / [apiUri], not [apiBase].
class X9Config {
  X9Config._();

  /// The address used when API_BASE is not given (or given empty) at build time.
  static const String fallbackApiBase = 'http://187.127.157.39/api/v1';

  /// Backend API base URL compiled into the APK (ends with /api/v1). May be EMPTY when the build passed
  /// `--dart-define=API_BASE=` with an empty value: use [defaultApiBase] / [effectiveApiBase] instead.
  static const String apiBase = String.fromEnvironment('API_BASE', defaultValue: fallbackApiBase);

  /// The server currently runs on an IP address with a self-signed certificate (Caddy `tls internal`).
  /// While that is true the app must trust that one host's certificate. Set ALLOW_SELF_SIGNED=false
  /// once the server has a domain name with a real certificate.
  static const bool allowSelfSigned = bool.fromEnvironment('ALLOW_SELF_SIGNED', defaultValue: true);

  /// Google Sign-In "Web client ID" from Firebase (Authentication > Sign-in method > Google).
  /// Needed so Google returns an ID token the X9 server can verify.
  static const String googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

  /// Lock the app again after it has been in the background this long.
  static const Duration relockAfter = Duration(seconds: 60);

  /// Compiled-in address, cleaned up (empty -> [fallbackApiBase], trailing slash removed, `/api/v1` added
  /// when only a host was given). Never empty.
  static String get defaultApiBase => ServerSettings.cleanDefault(apiBase);

  /// The address requests go to RIGHT NOW: the on-device override when one is saved, else [defaultApiBase].
  /// Read at call time, so a change in Server settings applies immediately.
  static String get effectiveApiBase => ServerSettings.effectiveApiBase;

  /// [effectiveApiBase] as a Uri (never throws).
  static Uri get apiUri => Uri.tryParse(effectiveApiBase) ?? Uri.parse(fallbackApiBase);
}
