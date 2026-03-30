import '../models/expense_model.dart';

class SettlementUtils {
  static double round2(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static double getNet(String a, String b, Map<String, Map<String, double>> debts) {
    final ab = debts[a]?[b] ?? 0.0;
    final ba = debts[b]?[a] ?? 0.0;
    return ab - ba;
  }

  static String getOtherUserId(Expense exp, String currentUserId) {
    return exp.participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => exp.payerId != currentUserId ? exp.payerId : '',
    );
  }

  static double getUserNetBalance(String currentUserId, Map<String, Map<String, double>> debts) {
    double total = 0;
    debts.forEach((from, map) {
      map.forEach((to, amount) {
        if (from == currentUserId) total -= amount;
        if (to == currentUserId) total += amount;
      });
    });
    return SettlementUtils.round2(total);
  }

  static Map<String, Map<String, double>> buildDebtsMap(List<Expense> expenses) {
    Map<String, Map<String, double>> debts = {};

    for (var exp in expenses) {
      if (exp.status == 'settled' && !exp.isSettlement) continue;
      
      final payerId = exp.payerId;
      exp.shares.forEach((participantId, shareAmount) {
        if (participantId == payerId) return;

        debts[participantId] ??= {};
        debts[participantId]![payerId] = SettlementUtils.round2(
            (debts[participantId]![payerId] ?? 0.0) + (shareAmount as num).toDouble());
      });
    }

    return debts;
  }

  /// Core spending calculation — single source of truth.
  /// [since] = null → All Time;  [since] = date → only expenses on/after that date.
  /// Always excludes settlements.
  static double calculateTotalSpent(List<Expense> expenses, String userId, {DateTime? since}) {
    double total = 0;
    for (final exp in expenses) {
      if (exp.isSettlement) continue;
      if (exp.payerId != userId) continue;
      if (since != null && exp.createdAt.isBefore(since)) continue;
      total += exp.amount;
    }
    return round2(total);
  }

  /// Convenience: spending for the current calendar month only.
  static double getMonthlySpending(List<Expense> expenses, String userId) {
    final now = DateTime.now();
    return calculateTotalSpent(expenses, userId, since: DateTime(now.year, now.month, 1));
  }

  /// Chart breakdown — same payer-only logic as calculateTotalSpent,
  /// but grouped by splitType for pie chart display.
  static Map<String, double> getUserSpendingBreakdown(
    List<Expense> expenses,
    String userId, {
    DateTime? since,
  }) {
    final Map<String, double> groups = {};

    for (final exp in expenses) {
      if (exp.isSettlement) continue;
      if (exp.payerId != userId) continue;
      if (since != null && exp.createdAt.isBefore(since)) continue;

      final key = exp.splitType;
      groups[key] = round2((groups[key] ?? 0) + exp.amount);
    }

    return groups;
  }

  /// Total amount current user owes others (sum of positive pairwise nets).
  static double getUserOwe(String userId, List<Expense> expenses) {
    final debts = buildDebtsMap(expenses);
    double total = 0;
    // Collect all unique peers
    final peers = <String>{};
    debts.forEach((from, map) {
      peers.add(from);
      map.forEach((to, _) => peers.add(to));
    });
    peers.remove(userId);
    for (final peer in peers) {
      final net = getNet(userId, peer, debts); // positive = I owe peer
      if (net > 0) total += net;
    }
    return round2(total);
  }

  /// Total amount others owe current user (sum of negative pairwise nets).
  static double getUserOwed(String userId, List<Expense> expenses) {
    final debts = buildDebtsMap(expenses);
    double total = 0;
    final peers = <String>{};
    debts.forEach((from, map) {
      peers.add(from);
      map.forEach((to, _) => peers.add(to));
    });
    peers.remove(userId);
    for (final peer in peers) {
      final net = getNet(userId, peer, debts); // negative = peer owes me
      if (net < 0) total += -net;
    }
    return round2(total);
  }
}
