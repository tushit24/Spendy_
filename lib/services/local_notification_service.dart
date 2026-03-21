import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();

  factory LocalNotificationService() => _instance;

  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // Initialize Timezone
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/notification_icon');

    // iOS Initialization (placeholder for future, even if Android only is required now)
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Local notification tapped: ${response.payload}');
      },
    );

    // Create Android Notification Channels for High Priority and Default
    await _createNotificationChannels();

    _isInitialized = true;
  }

  Future<void> _createNotificationChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'spendy_reminders', // id
          'Spendy Reminders', // name
          description: 'Daily and monthly expense reminders', // description
          importance: Importance.high,
        ),
      );

      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'spendy_group_alerts',
          'Group Activity Alerts',
          description: 'Notifications for group joins, expenses, etc.',
          importance: Importance.high,
        ),
      );

      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'spendy_summary',
          'Daily Summary & Reminders',
          description: 'Daily expense summary and settlement reminders',
          importance: Importance.defaultImportance,
        ),
      );
    }
  }

  /// Request Permissions (For Android 13+)
  Future<void> requestPermission() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      debugPrint("✅ Notification permission requested for Android");
    }
  }

  NotificationDetails _getReminderDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'spendy_reminders',
        'Spendy Reminders',
        channelDescription: 'Daily and monthly expense reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      ),
    );
  }

  NotificationDetails _getSummaryDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'spendy_summary',
        'Daily Summary & Reminders',
        channelDescription: 'Daily expense summary and settlement reminders',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'ic_notification',
      ),
    );
  }

  Future<void> showTestNotification() async {
    try {
      await _flutterLocalNotificationsPlugin.show(
        id: 999,
        title: 'Test Notification',
        body: 'If you see this, notifications work 🎉',
        notificationDetails: _getSummaryDetails(),
        payload: 'test_payload',
      );
      debugPrint("✅ Triggering test local notification... (ID 999)");
    } catch (e) {
      debugPrint("❌ Notification error: $e");
    }
  }

  /// Debug function to list pending notifications
  Future<void> debugNotifications() async {
    try {
      final pending =
          await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
      debugPrint("📌 Pending notifications: ${pending.length}");
      for (var p in pending) {
        debugPrint("   - ID: ${p.id}, Title: ${p.title}, Body: ${p.body}");
      }
    } catch (e) {
      debugPrint("❌ Error retrieving pending notifications: $e");
    }
  }

  /// Helper to get the next instance of a given time (hour, minute)
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  /// Schedules a daily reminder at 9 AM
  Future<void> scheduleDailyReminder() async {
    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id: 1,
        title: 'Spendy Daily Reminder',
        body: 'Did you spend anything today? Tap to record it!',
        scheduledDate: _nextInstanceOfTime(20, 0), // 8 PM
        notificationDetails: _getReminderDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('✅ Scheduling daily summary reminder at: ${_nextInstanceOfTime(20, 0)}');
    } catch (e) {
      debugPrint("❌ Notification error during daily schedule: $e");
    }
  }

  /// Cancel Daily Reminder
  Future<void> cancelDailyReminder() async {
    await _flutterLocalNotificationsPlugin.cancel(id: 1);
    debugPrint("Daily reminder cancelled");
  }

  /// Schedules a monthly reminder on the 1st of the month at 9 AM
  Future<void> scheduleMonthlyReminder() async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      1, // 1st day of the month
      9, // 9 AM
      0,
    );

    // Better calculation for exact 1st of next month
    if (scheduledDate.isBefore(now)) {
      DateTime nextMonth = DateTime(now.year, now.month + 1, 1, 9);
      scheduledDate = tz.TZDateTime.from(nextMonth, tz.local);
    }

    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id: 2,
        title: 'Monthly Review',
        body: 'Review and settle your monthly expenses.',
        scheduledDate: scheduledDate,
        notificationDetails: _getReminderDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Replaces androidAllowWhileIdle: true
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime, // Repeat monthly
      );
      debugPrint("✅ Scheduling monthly reminder at: $scheduledDate");
    } catch (e) {
      debugPrint("❌ Notification error during monthly schedule: $e");
    }
  }

  /// Cancel Monthly Reminder
  Future<void> cancelMonthlyReminder() async {
    await _flutterLocalNotificationsPlugin.cancel(id: 2);
    debugPrint("Monthly reminder cancelled");
  }

  // ───────────────────────────────────────────────────────────────
  // PART 4 — Daily Expense Summary Reminder at 9 PM
  // ───────────────────────────────────────────────────────────────

  /// Schedules a daily prompt at 9 PM. The actual content is computed
  /// separately by [ExpenseSummaryService.computeDailySummaryAndNotify].
  Future<void> scheduleDailySummaryReminder() async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      21, // 9 PM
      0,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id: 3,
        title: "Today's Spendy Summary",
        body: 'See what you spent and owe today.',
        scheduledDate: scheduledDate,
        notificationDetails: _getSummaryDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('✅ Scheduling daily summary reminder at: $scheduledDate');
    } catch (e) {
      debugPrint("❌ Notification error scheduling daily summary: $e");
    }
  }

  Future<void> cancelDailySummaryReminder() async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(id: 3);
      debugPrint('✅ Daily summary reminder cancelled');
    } catch (e) {
      debugPrint("❌ Error cancelling daily summary: $e");
    }
  }

  /// Shows an instant notification with computed daily expense totals.
  Future<void> showDailySummaryNotification({
    required int spent,
    required int owe,
    required int owed,
    required String symbol,
  }) async {
    final body = StringBuffer();
    if (spent > 0) body.write('You spent $symbol$spent today');
    if (owe > 0) {
      if (body.isNotEmpty) body.write(' • ');
      body.write('You owe $symbol$owe');
    }
    if (owed > 0) {
      if (body.isNotEmpty) body.write(' • ');
      body.write('You\'re owed $symbol$owed');
    }
    if (body.isEmpty) body.write('No expenses recorded today.');

    try {
      await _flutterLocalNotificationsPlugin.show(
        id: 3,
        title: "Today's Spendy Summary",
        body: body.toString(),
        notificationDetails: _getSummaryDetails(),
        payload: 'daily_summary',
      );
      debugPrint('✅ Daily summary notification shown: ${body.toString()}');
    } catch (e) {
      debugPrint("❌ Notification error showing daily summary: $e");
    }
  }

  // ───────────────────────────────────────────────────────────────
  // PART 5 — Settlement Reminder at 8 PM
  // ───────────────────────────────────────────────────────────────

  /// Schedules a future settlement reminder (if owed > 0)
  Future<void> scheduleSettlementReminderWithValue({
    required int totalOwed,
    required String symbol,
    required String toName,
  }) async {
    if (totalOwed <= 0) return;

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, 20, 0, // 8 PM
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1)); // Next day
    }

    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id: 4,
        title: 'Spendy Settlement Reminder',
        body: 'Reminder: You owe $symbol$totalOwed to $toName',
        scheduledDate: scheduledDate,
        notificationDetails: _getSummaryDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('✅ Scheduling settlement reminder at: $scheduledDate for $symbol$totalOwed');
    } catch (e) {
      debugPrint("❌ Notification error scheduling settlement: $e");
    }
  }

  Future<void> cancelSettlementReminder() async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(id: 4);
      debugPrint('✅ Settlement reminder cancelled');
    } catch (e) {
      debugPrint("❌ Error cancelling settlement reminder: $e");
    }
  }

  /// Shows an instant settlement reminder with the actual owed amount.
  Future<void> showSettlementReminderNotification({
    required int totalOwed,
    required String symbol,
  }) async {
    debugPrint('🔔 Settlement reminder shown: You owe $symbol$totalOwed');
    await _flutterLocalNotificationsPlugin.show(
      id: 4,
      title: 'Spendy Reminder',
      body: 'You still owe $symbol$totalOwed in your groups. Tap to settle.',
      notificationDetails: _getSummaryDetails(),
      payload: 'settlement_reminder',
    );
  }
}
