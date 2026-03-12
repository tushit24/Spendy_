import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:spendy/services/firestore_service.dart';

// The background message handler has been moved to main.dart for proper execution on Android.

/// A service to wrap Firebase Cloud Messaging logic.
class FCMService {
  static final FCMService _instance = FCMService._internal();

  factory FCMService() => _instance;

  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Track if we've initialized listeners
  bool _isInitialized = false;

  Future<void> init(String userId) async {
    if (_isInitialized) return;

    // 1. Request Permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('User granted permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // 2. Fetch Token and save to Firestore
      await _updateToken(userId);

      // Listen to token refreshes
      _fcm.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(userId, newToken);
      });

      // 3. Setup message handlers
      _setupMessageHandlers();

      _isInitialized = true;
    } else {
      debugPrint('User declined or has not accepted notification permissions');
    }
  }

  Future<void> _updateToken(String userId) async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        debugPrint("FCM Token: $token");
        await _saveTokenToFirestore(userId, token);
      }
    } catch (e) {
      debugPrint("Error fetching FCM token: $e");
    }
  }

  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      await FirestoreService.instance.updateUserToken(userId, token);
    } catch (e) {
      debugPrint("Error saving token to Firestore: $e");
    }
  }

  void _setupMessageHandlers() {
    // Top-level background handler needs to be registered in main.dart before app starts

    // Foreground messages handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint(
          'Message also contained a notification: ${message.notification}',
        );

        // Show local notification so the user sees it when the app is open
        _showForegroundNotification(message);
      }
    });

    // Handle clicks on notifications when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      // Handle navigation or data if needed
    });
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'spendy_group_alerts',
          'Group Activity Alerts',
          channelDescription: 'Notifications for group joins, expenses, etc.',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _localNotifications.show(
      id: message.hashCode,
      title: message.notification?.title ?? 'Spendy Alert',
      body: message.notification?.body,
      notificationDetails: platformChannelSpecifics,
      payload: jsonEncode(message.data),
    );
  }
}
