import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything the app keeps on the phone, in Android Keystore-backed encrypted storage.
class SessionStore {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true, resetOnError: true));

  static bool _healed = false;

  /// Reads one key. If Android cannot decrypt the stored data (reinstall, backup restore, changed lock screen) the
  /// unreadable storage is wiped once so the app starts clean (signed out) instead of failing to start.
  Future<String?> _safeRead(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      if (!_healed) {
        _healed = true;
        try {
          await _s.deleteAll();
        } catch (_) {}
      }
      return null;
    }
  }

  String? token;
  Map<String, dynamic>? user;
  String? deviceId;

  Future<void> load() async {
    // Each value is read on its own so one unreadable / corrupt entry cannot stop the others (or the app).
    try {
      token = await _safeRead('token');
    } catch (_) {
      token = null;
    }
    try {
      final u = await _safeRead('user');
      final d = (u == null || u.isEmpty) ? null : jsonDecode(u);
      user = d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      user = null;
    }
    try {
      deviceId = await _safeRead('device_id');
    } catch (_) {
      deviceId = null;
    }
    if (deviceId == null || deviceId!.isEmpty) {
      deviceId = _randomHex(16);
      try {
        await _s.write(key: 'device_id', value: deviceId);
      } catch (_) {}
    }
    // A token without a readable user record is still a login: the profile is fetched again on start.
  }

  bool get signedIn => token != null && token!.isNotEmpty;

  Future<void> saveLogin(String newToken, Map<String, dynamic> newUser) async {
    token = newToken;
    user = newUser;
    await _s.write(key: 'token', value: newToken);
    await _s.write(key: 'user', value: jsonEncode(newUser));
  }

  Future<void> saveUser(Map<String, dynamic> newUser) async {
    user = newUser;
    await _s.write(key: 'user', value: jsonEncode(newUser));
  }

  /// Sign out: forget the login and the device approval key. App-lock settings are kept.
  Future<void> clear() async {
    token = null;
    user = null;
    await _s.delete(key: 'token');
    await _s.delete(key: 'user');
    await _s.delete(key: 'device_key');
  }

  // ----- device approval key (signs every money call after the phone is unlocked) -----

  Future<String?> deviceKey() => _safeRead('device_key');

  /// Creates a new random 32-byte key; returns it base64-encoded for registration with the server.
  Future<String> createDeviceKey() async {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final b64 = base64Encode(bytes);
    await _s.write(key: 'device_key', value: b64);
    return b64;
  }

  Future<void> deleteDeviceKey() => _s.delete(key: 'device_key');

  /// hex(HMAC_SHA256(device_key, idempotencyKey|amount)) — see docs/APP-API-v2.md §0.
  Future<String?> signTxn(String idempotencyKey, int amount) async {
    final k = await deviceKey();
    if (k == null) return null;
    final mac = Hmac(sha256, base64Decode(k));
    return mac.convert(utf8.encode('$idempotencyKey|$amount')).toString();
  }

  // ----- app lock settings -----

  Future<String?> read(String key) => _safeRead(key);
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);

  static String _randomHex(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String newIdempotencyKey() => 'app-${DateTime.now().millisecondsSinceEpoch}-${_randomHex(8)}';
}
