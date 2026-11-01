import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Initializes and displays local notifications.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Invoked when the user taps a notification; [payload] is the invoice
  /// server id when the alert is about a specific bill.
  void Function(String? payload)? onTap;

  Future<void> initialize() async {
    if (_initialized) return;

    // Monochrome glyph: Android renders a coloured launcher icon as a white square.
    const android = AndroidInitializationSettings('@drawable/ic_stat_notify');
    // The iOS prompt is shown after sign-in by [requestPermission], not here.
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) =>
          onTap?.call(response.payload),
    );

    const channel = AndroidNotificationChannel(
      'gst_expense_alerts',
      'Expense alerts',
      description: 'Invoice approval and company announcements',
      importance: Importance.high,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Payload of the local notification that cold-started the app, if any.
  Future<String?> launchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details!.notificationResponse?.payload ?? '';
    } catch (_) {
      return null;
    }
  }

  /// Asks for POST_NOTIFICATIONS (Android 13+) once the user is signed in.
  Future<void> requestPermission() async {
    try {
      if (!_initialized) await initialize();
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // A denied or already-pending prompt must never block sign-in.
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'gst_expense_alerts',
        'Expense alerts',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_notify',
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}
