import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_messaging/firebase_messaging.dart' show FirebaseMessaging, RemoteMessage;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:x9_core/x9_core.dart';

/// Push notifications. Works without Firebase: when google-services.json is missing the app simply has no push.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _firebaseReady = false;
  bool _localReady = false;
  bool _listening = false;
  bool _refreshListening = false;
  int _nextId = 1;

  /// Called when the person taps a notification. Set by the root widget.
  void Function(Map<String, dynamic> data)? onOpen;

  /// A notification that opened the app before [onOpen] was set.
  Map<String, dynamic>? pendingOpen;

  bool get available => _firebaseReady;

  Future<void> init() async {
    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // v6.19 iPhone: permission is asked once after sign-in (FirebaseMessaging.requestPermission).
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse r) {
          final p = r.payload;
          if (p == null || p.isEmpty) return;
          try {
            final d = jsonDecode(p);
            if (d is Map) _open(Map<String, dynamic>.from(d));
          } catch (_) {}
        },
      );
      _localReady = true;
    } catch (_) {
      _localReady = false;
    }
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false; // push disabled: google-services.json missing
    }
    if (!_firebaseReady) return;
    try {
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessage.listen(_onForeground);
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) => _open(Map<String, dynamic>.from(m.data)));
      }
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) pendingOpen = Map<String, dynamic>.from(initial.data);
    } catch (_) {}
  }

  /// After sign-in: ask permission and register the FCM token with the X9 server.
  Future<void> registerToken() async {
    if (_localReady) {
      try {
        await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      } catch (_) {}
    }
    if (!_firebaseReady) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _send(token);
      if (!_refreshListening) {
        _refreshListening = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((t) => _send(t));
      }
    } catch (_) {}
  }

  Future<void> _send(String token) async {
    if (!SessionStore.instance.signedIn) return;
    try {
      await Api.instance.post('/app/device-token', {'token': token, 'platform': Platform.isIOS ? 'IOS' : 'ANDROID'});
    } catch (_) {}
  }

  void _onForeground(RemoteMessage m) {
    final n = m.notification;
    final title = n?.title ?? (m.data['title']?.toString() ?? 'X9');
    final body = n?.body ?? (m.data['body']?.toString() ?? '');
    show(title, body, data: Map<String, dynamic>.from(m.data));
  }

  Future<void> show(String title, String body, {Map<String, dynamic>? data}) async {
    if (!_localReady) return;
    try {
      await _local.show(
        _nextId++,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails('x9_alerts', 'X9 alerts', importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true, presentBadge: true),
        ),
        payload: data == null ? null : jsonEncode(data),
      );
    } catch (_) {}
  }

  void _open(Map<String, dynamic> data) {
    final cb = onOpen;
    if (cb == null) {
      pendingOpen = data;
    } else {
      cb(data);
    }
  }

  /// Delivers a notification that arrived before the app was ready.
  void flushPending() {
    final p = pendingOpen;
    if (p != null && onOpen != null) {
      pendingOpen = null;
      onOpen!(p);
    }
  }
}
