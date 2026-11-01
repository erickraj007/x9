import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// v6.17 offline mode (user app). Every successful GET of the person's data (home feed, shops, products, offers, wallet,
/// orders, bookings...) is saved on the phone; when there is no internet the app shows the saved copy and [offline] turns
/// true (the app shows an "Offline" bar). Pictures are saved the same way. Payments and other changes always need internet.
/// Saved data is per signed-in person and is wiped on sign-out.
class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  /// Turned on by the user app at start-up.
  bool enabled = false;

  /// true while the app is showing saved data because the server cannot be reached.
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  /// Who the saved data belongs to (a hash of the session token; empty = nobody signed in).
  String owner = '';

  Directory? _root;
  final Map<String, Uint8List> _mem = {}; // small in-memory picture cache
  static const _maxFiles = 600;
  int _writes = 0;

  static String ownerOf(String token) => crypto.sha1.convert(utf8.encode('x9|$token')).toString().substring(0, 16);

  static String _h(String s) => crypto.sha1.convert(utf8.encode(s)).toString();

  Future<Directory> _dir(String kind) async {
    _root ??= Directory('${(await getApplicationSupportDirectory()).path}/x9_offline');
    final d = Directory('${_root!.path}/$kind');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Only the person's own app data (not sign-in, OTP or device calls).
  static bool cacheable(String path) =>
      (path.startsWith('/app/') || path.startsWith('/geo/') || path == '/me' || path.startsWith('/me/') || path.startsWith('/cards')) &&
      !RegExp(r'otp|/auth/|device|token|share', caseSensitive: false).hasMatch(path);

  Future<void> putJson(String uri, dynamic json) async {
    if (!enabled || owner.isEmpty) return;
    try {
      final f = File('${(await _dir('json')).path}/${_h('$owner|$uri')}.json');
      await f.writeAsString(jsonEncode({'at': DateTime.now().toIso8601String(), 'v': json}), flush: false);
      if (++_writes % 50 == 0) unawaited(_prune('json'));
    } catch (_) {/* best effort */}
  }

  /// The saved copy of [uri] for the signed-in person, or null.
  Future<({dynamic value, DateTime? at})?> getJson(String uri) async {
    if (!enabled || owner.isEmpty) return null;
    try {
      final f = File('${(await _dir('json')).path}/${_h('$owner|$uri')}.json');
      if (!f.existsSync()) return null;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map) return null;
      return (value: m['v'], at: DateTime.tryParse('${m['at']}'));
    } catch (_) {
      return null;
    }
  }

  /// Signed picture links change, so a picture is saved under its path + version (`v`).
  static String imageKey(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final v = u.queryParameters['v'];
    return v == null ? u.replace(query: '').toString() : '${u.path}?v=$v';
  }

  /// Picture bytes: memory, then the phone, then the network (and saved for next time). null when unavailable.
  Future<Uint8List?> image(String url) async {
    final key = imageKey(url);
    final hit = _mem[key];
    if (hit != null) return hit;
    File? f;
    try {
      f = File('${(await _dir('img')).path}/${_h(key)}');
    } catch (_) {}
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        _remember(key, r.bodyBytes);
        if (f != null) unawaited(f.writeAsBytes(r.bodyBytes).then((_) {}, onError: (_) {}));
        return r.bodyBytes;
      }
    } catch (_) {/* offline: try the saved copy */}
    try {
      if (f != null && f.existsSync()) {
        final b = await f.readAsBytes();
        _remember(key, b);
        return b;
      }
    } catch (_) {}
    return null;
  }

  void _remember(String key, Uint8List b) {
    if (_mem.length > 80) _mem.remove(_mem.keys.first);
    _mem[key] = b;
  }

  Future<void> _prune(String kind) async {
    try {
      final files = (await _dir(kind)).listSync().whereType<File>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in files.skip(_maxFiles)) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  /// Sign-out: forget everything saved for the previous person.
  Future<void> clear() async {
    _mem.clear();
    offline.value = false;
    try {
      _root ??= Directory('${(await getApplicationSupportDirectory()).path}/x9_offline');
      if (_root!.existsSync()) await _root!.delete(recursive: true);
    } catch (_) {}
  }
}
