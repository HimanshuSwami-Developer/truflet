import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/network/json.dart';
import '../../data/repositories/notification_repository.dart';

/// Firebase Cloud Messaging: registers this device's token with the backend while a player is
/// signed in, shows pushes that arrive while the app is open, and reports taps on a notification.
///
/// Every step fails quietly: a device without Google Play services (or iOS, which has no
/// GoogleService-Info.plist yet) simply gets no pushes.
class PushService {
  final NotificationRepository _repo;
  PushService(this._repo);

  static const _channel = AndroidNotificationChannel(
    'turflet_alerts', // also set as FCM's default channel in AndroidManifest.xml
    'Match & booking alerts',
    description: 'Invites, join requests, payments and booking updates',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _registered; // token the backend currently has for this device
  bool _signedIn = false;

  /// A notification the player tapped, waiting until the home screen is up to be opened.
  Json? pendingOpen;

  /// Fires when [pendingOpen] is set.
  final _opens = StreamController<void>.broadcast();
  Stream<void> get opens => _opens.stream;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
        onDidReceiveNotificationResponse: (r) => _open(_decode(r.payload)),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
      // Registration tokens (getToken/onTokenRefresh) are what the backend sends to via FCM HTTP v1
      // `message.token`; the newer FID register() API targets a different send path.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((t) {
        if (_signedIn) _register(t);
      });

      // the app was launched by tapping a notification
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(initial.data);
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) _open(_decode(launch!.notificationResponse?.payload));
      _ready = true;
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// Call whenever the session changes: registers the token on sign-in, removes it on sign-out.
  Future<void> setSignedIn(bool signedIn) async {
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (!_ready) return;
    try {
      if (signedIn) {
        await FirebaseMessaging.instance.requestPermission();
        // ignore: deprecated_member_use
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await _register(token);
      } else if (_registered != null) {
        final token = _registered!;
        _registered = null;
        await _repo.unregisterDevice(token);
      }
    } catch (e) {
      debugPrint('Push token sync failed: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _repo.registerDevice(token, platform: defaultTargetPlatform.name);
      _registered = token;
    } catch (e) {
      debugPrint('Push token register failed: $e');
    }
  }

  /// FCM doesn't display notification messages while the app is in the foreground, so show it here.
  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      id: m.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification', // white "t" + ball glyph in the status bar
          color: const Color(0xFF143D2B),
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'), // full-colour app icon
        ),
      ),
      payload: jsonEncode(m.data),
    );
  }

  void _open(Map<String, dynamic> data) {
    pendingOpen = Map<String, dynamic>.from(data);
    _opens.add(null);
  }

  /// Hands over the tapped notification once (null when there is none).
  Json? takePendingOpen() {
    final p = pendingOpen;
    pendingOpen = null;
    return p;
  }

  static Map<String, dynamic> _decode(String? payload) {
    if (payload == null || payload.isEmpty) return {};
    try {
      return asMap(jsonDecode(payload));
    } catch (_) {
      return {};
    }
  }
}
