import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:gst_expense_scanner/core/services/notification_service.dart';

/// Firebase Cloud Messaging, configured at build time so no
/// google-services.json / GoogleService-Info.plist is needed:
///
///   flutter build appbundle --dart-define=FIREBASE_API_KEY=... \
///     --dart-define=FIREBASE_PROJECT_ID=... \
///     --dart-define=FIREBASE_SENDER_ID=... \
///     --dart-define=FIREBASE_ANDROID_APP_ID=... \
///     --dart-define=FIREBASE_IOS_APP_ID=...
///
/// Without these the app falls back to polling the notification inbox.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  bool _active = false;
  StreamSubscription<String>? _tokenRefresh;

  /// True once Firebase is initialised; local polling alerts are then skipped.
  bool get active => _active;

  /// Invoked for foreground pushes so the inbox can refresh.
  VoidCallback? onMessage;

  /// Invoked when the user taps a push while the app is in the background.
  void Function(Map<String, dynamic> data)? onOpened;

  Map<String, dynamic>? _launchMessage;

  /// Data of the push that cold-started the app, returned once.
  Map<String, dynamic>? takeLaunchMessage() {
    final data = _launchMessage;
    _launchMessage = null;
    return data;
  }

  static FirebaseOptions? get _options {
    final appId = switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidAppId,
      TargetPlatform.iOS => _iosAppId,
      _ => '',
    };
    if (kIsWeb || _apiKey.isEmpty || _projectId.isEmpty || _senderId.isEmpty || appId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
    );
  }

  Future<void> initialize() async {
    final options = _options;
    if (_active || options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpened?.call(m.data));
      _launchMessage = (await messaging.getInitialMessage())?.data;
      _active = true;
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    // iOS presents foreground pushes itself (see presentation options).
    if (notification != null && defaultTargetPlatform == TargetPlatform.android) {
      await NotificationService.instance.show(
        id: (message.messageId ?? notification.hashCode.toString()).hashCode & 0x7fffffff,
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: message.data['invoiceServerId']?.toString(),
      );
    }
    onMessage?.call();
  }

  /// Current device token, or null when push is not configured / denied.
  Future<String?> token() async {
    if (!_active) return null;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Push token unavailable: $e');
      return null;
    }
  }

  /// Re-registers the device whenever FCM rotates the token.
  void listenTokenRefresh(Future<void> Function(String token) register) {
    if (!_active) return;
    _tokenRefresh?.cancel();
    _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(register(token).catchError((_) {})),
    );
  }

  Future<void> signOut() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    if (!_active) return;
    try {
      await FirebaseMessaging.instance.unregister();
    } catch (_) {}
  }
}
