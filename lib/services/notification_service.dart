import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:spendy/services/fcm_service.dart';
import 'package:spendy/services/local_notification_service.dart';
import 'package:spendy/services/expense_summary_service.dart';
import 'package:googleapis_auth/auth_io.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final LocalNotificationService _localService = LocalNotificationService();
  final FCMService _fcmService = FCMService();
  final ExpenseSummaryService _summaryService = ExpenseSummaryService();

  Future<void> init(String userId) async {
    // Init local notifications
    await _localService.init();

    // Init FCM (Request permission, fetch token, listen)
    await _fcmService.init(userId);

    // Enable default reminders for logged-in user
    debugPrint('🔔 [NotificationService] Scheduling default reminders for $userId');
    await enableDailyReminder();
    await enableMonthlyReminder();
    await enableDailySummaryReminder();
    await checkSettlementReminder(userId);
  }

  // --- Local Notifications API ---

  Future<void> enableDailyReminder() async {
    await _localService.scheduleDailyReminder();
  }

  Future<void> disableDailyReminder() async {
    await _localService.cancelDailyReminder();
  }

  Future<void> enableMonthlyReminder() async {
    await _localService.scheduleMonthlyReminder();
  }

  Future<void> disableMonthlyReminder() async {
    await _localService.cancelMonthlyReminder();
  }

  Future<void> enableDailySummaryReminder() async {
    await _localService.scheduleDailySummaryReminder();
  }

  Future<void> disableDailySummaryReminder() async {
    await _localService.cancelDailySummaryReminder();
  }

  // Removed generic enable/disable settlement reminders as they are dynamic now

  /// Fetch today's expenses from Firestore and show an instant summary
  /// notification with real values. Useful to call at 9 PM or on demand.
  Future<void> scheduleDailySummary(String uid) async {
    await _summaryService.computeDailySummaryAndNotify(uid);
  }

  /// Query all owed expenses and show a settlement reminder if user
  /// owes money. Useful to call at 8 PM or on demand.
  Future<void> checkSettlementReminder(String uid) async {
    await _summaryService.computeSettlementAndNotify(uid);
  }

  Future<void> testNotification() async {
    await _localService.showTestNotification();
  }

  /// Sends a push notification to all members of a group except the specified actor.
  /// (Client-side implementation for college project. Uses HTTP V1 API directly)
  Future<void> sendGroupNotification({
    required String groupId,
    required String title,
    required String body,
    required String excludeUid,
    required List<String>
    targetTokens, // Pass tokens directly from GroupService
  }) async {
    if (targetTokens.isEmpty) return;

    try {
      // 1. Get an OAuth2 Access Token for the FCM Admin API
      final String serverAccessToken = await _getAccessToken();

      // IMPORTANT: Replace this with your actual Firebase Project ID
      const String projectId = 'spendy-e601d';
      final String endpoint =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      // 2. Loop through tokens and send (HTTP v1 requires sending 1 by 1)
      int successCount = 0;
      for (String token in targetTokens) {
        final response = await http.post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $serverAccessToken',
          },
          body: jsonEncode({
            'message': {
              'token': token,
              'notification': {'title': title, 'body': body},
              'data': {'groupId': groupId},
            },
          }),
        );

        if (response.statusCode == 200) {
          successCount++;
          debugPrint("✅ Push success for token: $token");
        } else {
          debugPrint("❌ Push failed for token: $token. Response: ${response.statusCode} - ${response.body}");
        }
      }

      debugPrint(
        'Successfully dispatched group notification to $successCount devices.',
      );
    } catch (e) {
      debugPrint("Error sending group notification: $e");
    }
  }

  /// Helper: Generates a short-lived OAuth2 token from a Service Account JSON
  /// NOTE: Storing service account keys in the app is INSECURE for production.
  /// This is used for educational/demo purposes ONLY.
  Future<String> _getAccessToken() async {
    // 1. Paste the exact contents of your Firebase Service Account JSON here
    final serviceAccountJson = {
      "type": "service_account",
      "project_id": "spendy-e601d",
      "private_key_id": "ca8bdd2bf8f2f6f87090fb7fe13ef7607c1d817e",
      "private_key":
          "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCxQ/BNVW8QGAaf\nAmmfvos7rluAtQMB4jQT2Ie9ZFkV2yV0PScnF48AydkPvwuCQNHg29OpxuVg4EDn\nsm2TCdunalzpou6QnsfFkPqlO2fk3eGdfa2WLTX8Xgi4k/lMcIakzmcPZQueaVDW\nE2FWXBLZ3wIVQXWp3yYyCEKCQMkP+i3Qiy9nsUKaqZ+UJop/rpTdkn4fzcmMAjWr\nB9FuvyvSGfwIvE4JF6Vyao5bKch1PXWGNqBcg3EXwl4H+YVF/Vek1XEBIg0fQtv9\nvIxRFB8LA5nKP0TY6p9cJLnfqUcvHmc0f2wSvBhbpfzlAqbhtuR2ibZlgqL0hnV3\nVlZ6N3ehAgMBAAECggEAA7xsE+EtVFBBUXgeTEbajeE0nf+SpudC1Dk/0SLMityh\nyzOfv9/r/GcEq2OKJU5i7gOMEDu4KWTIkWmODCeMyNhByY3My+EA0l3mHnXkUGtJ\nvkVAE5Zz2RQNSICb5DvJ5q7P9r/ZMRdEpCJn7odFwXBFDbght/kTR8IrTq35XtwM\nur8s8b7H6APcSZZTcJ2UzDRMwUSKgGeiE0mrLgf/vHggS+CSgfjyRh0ccb8Xfkv5\nV6xQfMQ9mUzM4hZ8SGWE21JR4h7VBmtJKvKAtRVstvFRivIauXIMYjIiQlH7Cp8w\nBbSmbS5cJQ2tWqzVz/0jTMKhMp9eoFTFDupZss6AvQKBgQDlKmt3Gpbs+tFkNhka\nwB61psee26cuDnqdjXNm1hNPK1j+2NWtZYiyNSnXMOH7AmlEgn213TXdJGNO+jFS\nQ360DGW+9gzZ4lRadsGv5o2/8/SWt0VN88FPa55haWjMMYSolkcEdZflr28Z5sI4\n4mdZz+i24N7XJ9xotc/1idkIlQKBgQDGBbrz2yuK/l1XmFIZh62ijh2WXnXh+cZV\n0zakA7fQJZkLpJiq0wOHf+dTJ5YcPQpI5WPofWhKsBDD62Esrwk517JtD9C8kwKx\nHcSquqjhx2ckwcVADHL4Ukm/eQisLeKmIG+EyiwPkSQ7GmNeUomLsGsqMS2keGaD\nnekM/1gT3QKBgQDQBHZyMceoK3Cgt16IYrY9i7uN3rLdYrU4iKqlQVNbvOxWwLsN\nX6n6obluJWgrsh+d2ZmE2NzI9PvUN9VHaA7+HnbJJY26xfBuAXiFVBF9mVN+77NQ\nNCBYGEc3AzjmiVhys56ZVKjiDCIcb9QDULgh1VDXmD2PLharUcYIiu1gFQKBgGia\nQE5ueQrcIPyThtLbm/ohbjmvPkAXjBBsGRH8sM1v/u9qjAa4nsWl59FCOQZDrDoj\nimoWTNAfP0vu+476CzqV2TfJQe9LDQH4gpnZLjrN9YsyHHsf2F+aQEC3s8AYIQC2\nY5JWpX23otbhspnxqZyznXhVMBIQU7603JW0EJe1AoGBAMcrdKKlgxGJp6ELjzNj\ngmvJiuUUXdOoGYQmpyftbnSFPQE2f+wepj0bpogHgulXcOOtMYVxPNYuU/ARvpqI\nv2rRdCc491WW6X1xpyl5yPE0A/Qkrz7r+juitItD+xpEbjSPW8WqHtGp2TodqoWU\n0/QoGA4bsUh360X+AHOhG53c\n-----END PRIVATE KEY-----\n",
      "client_email":
          "firebase-adminsdk-fbsvc@spendy-e601d.iam.gserviceaccount.com",
      "client_id": "105057557680034268846",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url":
          "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url":
          "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40spendy-e601d.iam.gserviceaccount.com",
      "universe_domain": "googleapis.com",
    };

    if (serviceAccountJson.isEmpty) {
      debugPrint('WARNING: Service Account JSON is empty. Push will fail.');
      return '';
    }

    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

    final authClient = await clientViaServiceAccount(credentials, scopes);
    final token = authClient.credentials.accessToken.data;
    authClient.close();

    return token;
  }
}
