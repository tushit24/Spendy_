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
        AndroidInitializationSettings('ic_notification');

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
    await _flutterLocalNotificationsPlugin.show(
      id: 0,
      title: 'Test Notification',
      body: 'This is a test notification from SPENDY.',
      notificationDetails: _getReminderDetails(),
      payload: 'test_payload',
    );
    debugPrint("🔔 Triggering test local notification...");
  }

  /// Schedules a daily reminder at 9 AM
  Future<void> scheduleDailyReminder() async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      9, // 9 AM
      0,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: 1,
      title: 'Daily Reminder',
      body: 'Don’t forget to add today’s expenses!',
      scheduledDate: scheduledDate,
      notificationDetails: _getReminderDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
    );
    debugPrint("✅ Daily reminder scheduled successfully for: $scheduledDate");
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

    if (scheduledDate.isBefore(now)) {
      // Move to next month
      scheduledDate = tz.TZDateTime(
        tz.local,
        now.year + (now.month == 12 ? 1 : 0),
        now.month == 12 ? 1 : now.month + 1,
        1,
        9,
        0,
      );
    }

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: 2,
      title: 'Monthly Review',
      body: 'Review and settle your monthly expenses.',
      scheduledDate: scheduledDate,
      notificationDetails: _getReminderDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents:
          DateTimeComponents.dayOfMonthAndTime, // Repeat monthly
    );
    debugPrint("Monthly reminder scheduled at $scheduledDate");
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

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: 3,
      title: "Today's Spendy Summary",
      body: 'See what you spent and owe today.',
      scheduledDate: scheduledDate,
      notificationDetails: _getSummaryDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    debugPrint('✅ Daily summary reminder scheduled for: $scheduledDate');
  }

  Future<void> cancelDailySummaryReminder() async {
    await _flutterLocalNotificationsPlugin.cancel(id: 3);
    debugPrint('Daily summary reminder cancelled');
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

    await _flutterLocalNotificationsPlugin.show(
      id: 3,
      title: "Today's Spendy Summary",
      body: body.toString(),
      notificationDetails: _getSummaryDetails(),
      payload: 'daily_summary',
    );
    debugPrint('🔔 Daily summary notification shown: ${body.toString()}');
  }

  // ───────────────────────────────────────────────────────────────
  // PART 5 — Settlement Reminder at 8 PM
  // ───────────────────────────────────────────────────────────────

  /// Schedules a daily settlement check at 8 PM.
  Future<void> scheduleSettlementReminder() async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      20, // 8 PM
      0,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: 4,
      title: 'Spendy Reminder',
      body: 'You still have unsettled expenses. Tap to settle up.',
      scheduledDate: scheduledDate,
      notificationDetails: _getSummaryDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    debugPrint('✅ Settlement reminder scheduled for: $scheduledDate');
  }

  Future<void> cancelSettlementReminder() async {
    await _flutterLocalNotificationsPlugin.cancel(id: 4);
    debugPrint('Settlement reminder cancelled');
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
      body:
          'You still owe $symbol$totalOwed in your groups. Tap to settle.',
      notificationDetails: _getSummaryDetails(),
      payload: 'settlement_reminder',
    );
  }
}
