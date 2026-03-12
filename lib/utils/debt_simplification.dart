import 'package:spendy/models/expense_model.dart';

class DebtMatch {
  final String from;
  final String to;
  final double amount;

  DebtMatch({
    required this.from,
    required this.to,
    required this.amount,
  });
}

class DebtSimplifier {
  /// Consolidates all expenses in a group into minimum transactions.
  static List<DebtMatch> simplifyDebts(List<Expense> expenses, {String? groupId}) {
    // 1. Calculate net balances for every user
    // A positive balance means the user is owed money (creditor)
    // A negative balance means the user owes money (debtor)
    Map<String, double> balances = {};

    for (var expense in expenses) {
      if (expense.status == 'settled') continue;
      // Optional: Filter by group if needed
      if (groupId != null && expense.groupId != groupId) continue;

      final payer = expense.payerId;
      final amount = expense.amount;

      // Payer gets credit for their payment
      balances[payer] = (balances[payer] ?? 0) + amount;

      // Each participant owes their share
      expense.shares.forEach((participantId, shareAmount) {
        balances[participantId] = (balances[participantId] ?? 0) - shareAmount;
      });
    }

    // 2. Separate into creditors and debtors
    List<MapEntry<String, double>> creditors = [];
    List<MapEntry<String, double>> debtors = [];

    balances.forEach((userId, balance) {
      // Threshold to avoid floating point issues
      if (balance > 0.01) {
        creditors.add(MapEntry(userId, balance));
      } else if (balance < -0.01) {
        debtors.add(MapEntry(userId, -balance)); // Store absolute debt amount
      }
    });

    // Sort descending by amount to optimize the greedy approach
    // (Pair largest debtors with largest creditors first)
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    // 3. Match debtors to creditors
    List<DebtMatch> transactions = [];
    int i = 0; // Creditor index
    int j = 0; // Debtor index

    while (i < creditors.length && j < debtors.length) {
      String creditorId = creditors[i].key;
      double creditAmount = creditors[i].value;

      String debtorId = debtors[j].key;
      double debtAmount = debtors[j].value;

      // The transaction amount is the minimum of what's owed and what's owed-to
      double amount = creditAmount < debtAmount ? creditAmount : debtAmount;

      transactions.add(DebtMatch(
        from: debtorId,
        to: creditorId,
        amount: amount,
      ));

      // Update remaining amounts
      creditors[i] = MapEntry(creditorId, creditAmount - amount);
      debtors[j] = MapEntry(debtorId, debtAmount - amount);

      // Move pointers if balance is resolved
      if (creditors[i].value < 0.01) {
        i++;
      }
      if (debtors[j].value < 0.01) {
        j++;
      }
    }

    return transactions;
  }
}
