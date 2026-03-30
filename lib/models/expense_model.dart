import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String id;
  final String groupId;
  final String title;
  final double amount;
  final String payerId;
  final List<String> participants;
  final String splitType; // 'Equally' / 'Custom'
  final Map<String, double> shares;
  final DateTime createdAt;
  final String status; // 'owed' / 'settled'

  /// Central helper — use this instead of raw `status == 'settled'` checks.
  bool get isSettled {
    return status.toLowerCase().trim() == 'settled';
  }

  /// Returns true if this expense is a settlement (offsetting) transaction.
  bool get isSettlement {
    return title.toLowerCase().trim() == 'settlement' ||
        splitType.toLowerCase().trim() == 'settlement';
  }

  Expense({
    required this.id,
    required this.groupId,
    required this.title,
    required this.amount,
    required this.payerId,
    required this.participants,
    required this.splitType,
    required this.shares,
    required this.createdAt,
    required this.status,
  });

  factory Expense.fromMap(String id, Map<String, dynamic> data) {
    return Expense(
      id: id,
      groupId: data['groupId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      payerId: data['payerId'] as String? ?? '',
      participants: List<String>.from(data['participants'] ?? const []),
      splitType: data['splitType'] as String? ?? 'Equally',
      shares: (data['shares'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: (data['status'] as String? ?? 'owed').toLowerCase().trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'title': title,
      'amount': amount,
      'payerId': payerId,
      'participants': participants,
      'splitType': splitType,
      'shares': shares,
      'createdAt': createdAt,
      'status': status,
    };
  }
}
