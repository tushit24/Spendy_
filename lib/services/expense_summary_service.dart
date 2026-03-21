import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';
import 'local_notification_service.dart';

/// Service that computes expense summaries from Firestore and triggers
/// the corresponding local notifications.
class ExpenseSummaryService {
  static final ExpenseSummaryService _instance =
      ExpenseSummaryService._internal();

  factory ExpenseSummaryService() => _instance;

  ExpenseSummaryService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final LocalNotificationService _localService = LocalNotificationService();

  // ─────────────────────────────────────────────────────────────
  // PART 4 — Daily Expense Summary
  // ─────────────────────────────────────────────────────────────

  /// Queries today's expenses for [uid], computes totals, and shows a local
  /// summary notification. Call this from a background isolate or WorkManager
  /// worker at 9 PM.
  Future<void> computeDailySummaryAndNotify(String uid) async {
    debugPrint('📊 [ExpenseSummaryService] Computing daily summary for $uid');
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snap = await _db
          .collection('expenses')
          .where('participants', arrayContains: uid)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      double spent = 0;
      double owe = 0;
      double owed = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final double amount = (data['amount'] as num?)?.toDouble() ?? 0;
        final String payerId = data['payerId'] as String? ?? '';
        final String status = data['status'] as String? ?? '';
        final Map<String, dynamic> shares =
            (data['shares'] as Map<String, dynamic>?) ?? {};

        final double myShare = (shares[uid] as num?)?.toDouble() ?? 0;

        spent += myShare;

        if (payerId == uid) {
          if (status == 'owed') {
            owed += (amount - myShare);
          }
        } else {
          if (status == 'owed') {
            owe += myShare;
          }
        }
      }

      // Get currency symbol
      final userDoc = await FirestoreService.instance.streamUser(uid).first;
      final currencyCode = userDoc.currency;
      final symbol = _getSymbol(currencyCode);

      debugPrint(
        '📊 [ExpenseSummaryService] Summary — spent: $symbol${spent.toInt()} owe: $symbol${owe.toInt()} owed: $symbol${owed.toInt()}',
      );

      await _localService.showDailySummaryNotification(
        spent: spent.toInt(),
        owe: owe.toInt(),
        owed: owed.toInt(),
        symbol: symbol,
      );
    } catch (e) {
      debugPrint('❌ [ExpenseSummaryService] Daily summary error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PART 5 — Settlement Reminder
  // ─────────────────────────────────────────────────────────────

  /// Queries all unpaid expenses for [uid], and if the user owes money,
  /// shows an instant reminder notification. Call this at 8 PM daily.
  Future<void> computeSettlementAndNotify(String uid) async {
    debugPrint(
      '💸 [ExpenseSummaryService] Checking settlement reminder for $uid',
    );
    try {
      final snap = await _db
          .collection('expenses')
          .where('participants', arrayContains: uid)
          .where('status', isEqualTo: 'owed')
          .get();

      double totalOwed = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final String payerId = data['payerId'] as String? ?? '';
        final Map<String, dynamic> shares =
            (data['shares'] as Map<String, dynamic>?) ?? {};

        // Only count expenses where SOMEONE ELSE paid — meaning I owe them
        if (payerId != uid) {
          final double myShare = (shares[uid] as num?)?.toDouble() ?? 0;
          totalOwed += myShare;
        }
      }

      // Get currency symbol
      final userDoc = await FirestoreService.instance.streamUser(uid).first;
      final currencyCode = userDoc.currency;
      final symbol = _getSymbol(currencyCode);

      debugPrint(
        '💸 [ExpenseSummaryService] Total owed by user: $symbol${totalOwed.toInt()}',
      );

      if (totalOwed > 0) {
        await _localService.scheduleSettlementReminderWithValue(
          totalOwed: totalOwed.toInt(),
          symbol: symbol,
          toName: 'your group members',
        );
      } else {
        await _localService.cancelSettlementReminder();
        debugPrint(
          '✅ [ExpenseSummaryService] User owes nothing — no reminder sent.',
        );
      }
    } catch (e) {
      debugPrint('❌ [ExpenseSummaryService] Settlement reminder error: $e');
    }
  }

  // Currency Helper
  String _getSymbol(String code) {
    if (code == 'USD') return r'$';
    if (code == 'EUR') return '€';
    if (code == 'GBP') return '£';
    return '₹';
  }
}
