import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../services/google_auth.dart';
import '../services/location.dart';
import '../util/helpers.dart';

/// Root navigator, used for the lock screen, sign-out and notification taps.
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

/// App-wide state shared by the home screen, drawer and wallet pages (balances, feed, badge counts).
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  Map<String, dynamic>? feed;
  bool loadingFeed = false;
  Object? feedError;

  int clubBalance = 0;

  /// True once balances came from the server (amount screens then check against them).
  bool balancesKnown = false;
  int cardBalance = 0;
  int unread = 0;
  int pendingLinks = 0;

  /// Set by the root gate: re-evaluates sign-in / lock / device state.
  VoidCallback? onSessionChanged;

  bool _signingOut = false;

  Map<String, dynamic> get user => SessionStore.instance.user ?? const <String, dynamic>{};

  String get city {
    final c = str(asMap(feed?['location'])['city']);
    if (c.isNotEmpty) return c;
    return LocationService.instance.city ?? 'Set location';
  }

  Future<void> refreshFeed() async {
    loadingFeed = true;
    notifyListeners();
    try {
      final r = asMap(await Api.instance.get('/app/feed', LocationService.instance.query));
      feed = r;
      feedError = null;
      final b = asMap(r['balances']);
      clubBalance = asInt(b['club_wallet']);
      cardBalance = asInt(b['prepaid_card']);
      balancesKnown = b.isNotEmpty;
      unread = asInt(r['unread_notifications']);
      pendingLinks = asInt(r['pending_payment_links']);
    } catch (e) {
      feedError = e;
    } finally {
      loadingFeed = false;
      notifyListeners();
    }
  }

  /// Light refresh after a payment / transfer.
  Future<void> refreshBalances() async {
    try {
      final r = asMap(await Api.instance.get('/app/wallet'));
      final b = asMap(r['balances']);
      if (b.containsKey('USER_MAIN')) clubBalance = asInt(b['USER_MAIN']);
      if (b.containsKey('USER_CARD')) cardBalance = asInt(b['USER_CARD']);
      if (b.containsKey('USER_MAIN')) balancesKnown = true;
      notifyListeners();
    } catch (_) {}
  }

  /// Wallet balance for amount checks, or null when not loaded yet.
  int? get knownClubBalance => balancesKnown ? clubBalance : null;

  void setUnread(int v) {
    unread = v < 0 ? 0 : v;
    notifyListeners();
  }

  void setPendingLinks(int v) {
    pendingLinks = v < 0 ? 0 : v;
    notifyListeners();
  }

  /// The stored user (name, VIP, mobile) changed: redraw the drawer / headers.
  void signedInUserChanged() => notifyListeners();

  void signedIn() {
    rootNavKey.currentState?.popUntil((r) => r.isFirst);
    onSessionChanged?.call();
  }

  /// Sign out. [server] = false when the server already rejected the token (401).
  Future<void> signOut({bool server = true}) async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      if (server && SessionStore.instance.signedIn) {
        try {
          await Api.instance.delete('/app/device-key');
        } catch (_) {}
        try {
          await Api.instance.post('/auth/logout');
        } catch (_) {}
      }
      await GoogleAuth.instance.signOut();
      LocationService.instance.stopHeartbeat();
      await SessionStore.instance.clear();
      feed = null;
      feedError = null;
      clubBalance = 0;
      cardBalance = 0;
      balancesKnown = false;
      unread = 0;
      pendingLinks = 0;
      notifyListeners();
      rootNavKey.currentState?.popUntil((r) => r.isFirst);
      onSessionChanged?.call();
    } finally {
      _signingOut = false;
    }
  }
}
