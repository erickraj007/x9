import 'dart:async';

import 'package:app_links/app_links.dart';

/// Offer links: `x9://offer/CODE` and `https://HOST/o/CODE` (the share link of an offer).
///
/// The root widget sets [onOffer]; links that arrive before the app is signed in / unlocked wait in [pendingRef]
/// until [flushPending] is called.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Opens the offer with this code (or uuid). Set by the root widget.
  void Function(String ref)? onOffer;

  /// An offer link received while the app could not show it yet.
  String? pendingRef;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    try {
      _sub = _links.uriLinkStream.listen(_handle, onError: (Object _) {});
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  /// The offer code / uuid inside a link, or null when it is not an offer link.
  static String? offerRefOf(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final parts = <String>[
      if (scheme == 'x9' && uri.host.isNotEmpty) uri.host.toLowerCase(),
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    if (scheme == 'x9') {
      if (parts.length >= 2 && parts.first == 'offer') return parts[1];
      return null;
    }
    if (scheme == 'https' || scheme == 'http') {
      if (parts.length >= 2 && parts.first == 'o') return parts[1];
    }
    return null;
  }

  void _handle(Uri uri) {
    final ref = offerRefOf(uri);
    if (ref == null || ref.isEmpty) return;
    final cb = onOffer;
    if (cb == null) {
      pendingRef = ref;
    } else {
      cb(ref);
    }
  }

  /// Delivers a link that arrived before the app was ready.
  void flushPending() {
    final r = pendingRef;
    final cb = onOffer;
    if (r != null && cb != null) {
      pendingRef = null;
      cb(r);
    }
  }
}
