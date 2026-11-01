import 'package:google_sign_in/google_sign_in.dart';
import 'package:x9_core/x9_core.dart';

/// Google Sign-In on the phone; the ID token is verified by the X9 server (POST /auth/google).
class GoogleAuth {
  GoogleAuth._();
  static final GoogleAuth instance = GoogleAuth._();

  GoogleSignIn? _gs;

  GoogleSignIn get _client => _gs ??= GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: X9Config.googleServerClientId.isEmpty ? null : X9Config.googleServerClientId,
      );

  /// Returns the Google ID token, or null when the person closed the account picker.
  Future<String?> signIn() async {
    // Always show the account chooser (a previous session may still be cached).
    try {
      await _client.signOut();
    } catch (_) {}
    final acc = await _client.signIn();
    if (acc == null) return null;
    final auth = await acc.authentication;
    final token = auth.idToken;
    if (token == null || token.isEmpty) {
      throw Exception('Google did not return an ID token. The app needs GOOGLE_SERVER_CLIENT_ID (Web client ID) at build time.');
    }
    return token;
  }

  Future<void> signOut() async {
    try {
      await _client.signOut();
    } catch (_) {}
  }
}
