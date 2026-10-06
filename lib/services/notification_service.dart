import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

/// Must be a top-level (or static) function — Firebase Cloud Messaging
/// runs this in a separate isolate when a data message arrives while the
/// app is fully backgrounded/terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing extra needed here for notification-only messages — Android
  // displays those automatically using the payload's notification block.
  // This handler exists so data-only messages can still be processed if
  // the app adds that later (e.g. silently refreshing meal-plan data).
}

/// Wraps Firebase Cloud Messaging: requests notification permission,
/// registers the device's FCM token against the signed-in user (so a
/// push can be targeted at them later, e.g. via Firebase Console's
/// "Send test message"), and shows a local system notification when a
/// message arrives while the app is open in the foreground (Android
/// doesn't do this automatically — only background/terminated messages
/// auto-display).
class NotificationService {
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      'sarap_default_channel',
      'SARAP Notifications',
      description: 'Meal plan reminders and app updates',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Show a local notification whenever a message arrives while the
    // app is open (foreground) — background/terminated messages are
    // already handled by the OS automatically.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'sarap_default_channel',
            'SARAP Notifications',
            channelDescription: 'Meal plan reminders and app updates',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });
  }

  /// Saves this device's current FCM token against the signed-in user's
  /// Firestore document, and keeps it updated if it ever refreshes.
  /// Call this after login/registration succeeds.
  static Future<void> registerTokenForCurrentUser() async {
    final uid = FirebaseService.currentUid;
    if (uid == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'fcmToken': token}, SetOptions(merge: true));
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'fcmToken': newToken}, SetOptions(merge: true));
      });
    } catch (_) {
      // Non-fatal — the app works fine without a registered token, it
      // just means this device can't be individually targeted yet.
    }
  }

  /// Shows a purely local notification (no Firebase round-trip) — used
  /// for on-device meal-time reminders that don't need a server.
  static Future<void> showLocal({required String title, required String body}) async {
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sarap_default_channel',
          'SARAP Notifications',
          channelDescription: 'Meal plan reminders and app updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
