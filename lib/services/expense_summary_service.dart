import 'package:flutter/foundation.dart';
import 'firestore_service.dart';
import 'local_notification_service.dart';
import '../models/expense_model.dart';
import '../utils/settlement_utils.dart';

/// Service that computes expense summaries from Firestore and triggers
/// the corresponding local notifications.
class ExpenseSummaryService {
  static final ExpenseSummaryService _instance =
      ExpenseSummaryService._internal();

  factory ExpenseSummaryService() => _instance;

  ExpenseSummaryService._internal();

  final LocalNotificationService _localService = LocalNotificationService();

  // ─────────────────────────────────────────────────────────────
  // PART 4 — Daily Expense Summary
  // ─────────────────────────────────────────────────────────────

  /// Queries ALL expenses for [uid], computes ledger-based owe/owed via
  /// SettlementUtils, and shows a local summary notification.
  Future<void> computeDailySummaryAndNotify(String uid) async {
    debugPrint('📊 [ExpenseSummaryService] Computing daily summary for $uid');
    try {
      // Fetch ALL unfiltered expenses (one-shot from the stream)
      final List<Expense> expenses =
          await FirestoreService.instance.streamUserExpenses(uid).first;

      // Ledger-based calculation — single source of truth
      final double owe = SettlementUtils.getUserOwe(uid, expenses);
      final double owed = SettlementUtils.getUserOwed(uid, expenses);

      // Spending today (non-settlement, payer-only)
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final double spent =
          SettlementUtils.calculateTotalSpent(expenses, uid, since: startOfDay);

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

  /// Queries ALL expenses for [uid], computes ledger-based owe via
  /// SettlementUtils, and if the user owes money, shows a reminder.
  Future<void> computeSettlementAndNotify(String uid) async {
    debugPrint(
      '💸 [ExpenseSummaryService] Checking settlement reminder for $uid',
    );
    try {
      // Fetch ALL unfiltered expenses (one-shot from the stream)
      final List<Expense> expenses =
          await FirestoreService.instance.streamUserExpenses(uid).first;

      // Ledger-based calculation — single source of truth
      final double totalOwed = SettlementUtils.getUserOwe(uid, expenses);

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
