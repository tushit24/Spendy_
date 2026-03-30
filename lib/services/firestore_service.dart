import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import 'notification_service.dart';

class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // USERS

  Future<void> createUserIfNotExists(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      final appUser = AppUser(
        uid: user.uid,
        name: user.displayName ?? '',
        email: user.email ?? '',
        photoUrl: user.photoURL,
        createdAt: DateTime.now(),
      );
      await ref.set(appUser.toMap());
    }
  }

  Stream<AppUser> streamUser(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => AppUser.fromMap(snap.id, snap.data() ?? {}));
  }

  Future<AppUser?> getUser(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    if (!snap.exists || snap.data() == null) return null;
    return AppUser.fromMap(snap.id, snap.data()!);
  }

  Future<void> updateUserName(String uid, String name) {
    return _db.collection('users').doc(uid).update({'name': name});
  }

  Future<void> updateUserPhotoUrl(String uid, String url) {
    return _db.collection('users').doc(uid).update({'photoUrl': url});
  }

  Future<void> updateUserCurrency(String uid, String currency) {
    return _db.collection('users').doc(uid).update({'currency': currency});
  }

  Future<void> updateUserToken(String uid, String token) {
    return _db.collection('users').doc(uid).update({'fcmToken': token});
  }

  Future<void> updateUserUpiId(String uid, String upiId) {
    return _db.collection('users').doc(uid).update({'upiId': upiId});
  }

  // ── Spent Counter Reset ──────────────────────────────────────────

  /// Saves the current timestamp as the user's reset date.
  Future<void> updateResetDate(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .update({'resetDate': FieldValue.serverTimestamp()});
  }

  /// Returns the stored resetDate for the user, or null.
  Future<DateTime?> getResetDate(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final ts = snap.data()?['resetDate'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  /// Stream expenses for [uid] filtered by [since] date (inclusive).
  /// Pass null for [since] to get all time.
  Stream<List<Expense>> streamUserExpensesFiltered(
    String uid, {
    DateTime? since,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('expenses')
        .where('participants', arrayContains: uid);

    if (since != null) {
      q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }

    return q
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Expense.fromMap(d.id, d.data())).toList());
  }

  Future<void> updateUserReminderSettings(
    String uid, {
    bool? daily,
    bool? monthly,
  }) async {
    final Map<String, dynamic> updates = {};
    if (daily != null) updates['requestDailyReminder'] = daily;
    if (monthly != null) updates['requestMonthlyReminder'] = monthly;
    if (updates.isNotEmpty) {
      await _db.collection('users').doc(uid).update(updates);
    }
  }

  Future<List<AppUser>> getUsers(List<String> uids) async {
    if (uids.isEmpty) return [];
    // Firestore whereIn is limited to 10. We'll chunk it if needed,
    // but for this app's scale, we'll assume small groups or handle simple splitting.
    final users = <AppUser>[];
    final chunks = <List<String>>[];
    for (var i = 0; i < uids.length; i += 10) {
      chunks.add(uids.sublist(i, min(i + 10, uids.length)));
    }

    for (var chunk in chunks) {
      final snap = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      users.addAll(snap.docs.map((d) => AppUser.fromMap(d.id, d.data())));
    }
    return users;
  }

  // GROUPS

  Stream<List<Group>> streamUserGroups(String uid) {
    return _db
        .collection('groups')
        .where('members', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Group.fromMap(d.id, d.data())).toList(),
        );
  }
  // GROUPS logic moved to GroupService.dart
  // Keeping streamUserGroups for backward compatibility if needed temporarily,
  // but recommended to use GroupService.

  // EXPENSES

  Future<void> addExpense(Expense expense) async {
    if (expense.groupId == null || expense.groupId!.isEmpty) {
      throw Exception('groupId is required for expenses');
    }

    final ref = _db
        .collection('expenses')
        .doc();
        
    await ref.set(
      expense.toMap()..['createdAt'] = FieldValue.serverTimestamp(),
    );

    if (expense.groupId != null && expense.groupId!.isNotEmpty) {
      String payerName = 'Someone';
      String groupName = 'a group';

      try {
        final userDoc = await _db
            .collection('users')
            .doc(expense.payerId)
            .get();
        if (userDoc.exists) payerName = userDoc.data()?['name'] ?? 'Someone';

        final groupDoc = await _db
            .collection('groups')
            .doc(expense.groupId)
            .get();
        if (groupDoc.exists) groupName = groupDoc.data()?['name'] ?? 'a group';
      } catch (e) {
        // Fallback to defaults if fetch fails
      }

      final userDoc = await _db.collection('users').doc(expense.payerId).get();
      final currencyCode = userDoc.data()?['currency'] as String? ?? 'INR';
      final symbol = _getSymbol(currencyCode);
      
      final String title = expense.isSettlement
          ? '$payerName settled $symbol${expense.amount.toStringAsFixed(0)} in $groupName'
          : '$payerName added $symbol${expense.amount.toStringAsFixed(0)} in $groupName';
      final String body = expense.isSettlement
          ? 'Settlement'
          : (expense.title.isNotEmpty
              ? '${expense.title} • Split ${expense.splitType}'
              : 'New group expense');

      await _notifyGroupMembers(
        groupId: expense.groupId!,
        title: title,
        body: body,
        excludeUid: expense.payerId,
      );
    }
  }

  Stream<List<Expense>> streamUserExpenses(String uid) {
    return _db
        .collection('expenses')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Expense.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<Expense>> streamFilteredExpenses({
    required String uid,
    String? groupId,
    String? userFilterUid,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('expenses');

    if (groupId != null && groupId.isNotEmpty && groupId != 'All') {
      q = q.where('groupId', isEqualTo: groupId);
    } else {
      q = q.where('participants', arrayContains: uid);
    }

    // If filtering by another user, Firestore cannot OR two conditions directly.
    // We fall back to in-memory filter on a broader query.
    if (userFilterUid != null && userFilterUid.isNotEmpty && userFilterUid != 'All') {
      return q
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => Expense.fromMap(d.id, d.data()))
                .where(
                  (e) =>
                      e.payerId == userFilterUid ||
                      e.participants.contains(userFilterUid),
                )
                .toList(),
          );
    }

    return q
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Expense.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<Expense>> streamGroupExpenses(String groupId) {
    return _db
        .collection('expenses')
        .where('groupId', isEqualTo: groupId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Expense.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<List<Expense>> getExpensesOnce(String groupId) async {
    final snapshot = await _db
        .collection('expenses')
        .where('groupId', isEqualTo: groupId)
        .get();
        
    return snapshot.docs
        .map((d) => Expense.fromMap(d.id, d.data()))
        .toList();
  }


  Future<void> deleteExpense(String expenseId) {
    return _db.collection('expenses').doc(expenseId).delete();
  }

  Future<void> updateExpenseShares(String expenseId, Map<String, double> shares) async {
    await _db.collection('expenses').doc(expenseId).update({'shares': shares});
  }

  /// ONE-TIME FIX SCRIPT: Restores original shares for settled expenses whose shares were zeroed out.
  Future<void> restoreSettledShares() async {
    final snapshot = await _db.collection('expenses').where('status', isEqualTo: 'settled').get();
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final shares = data['shares'] as Map<String, dynamic>? ?? {};
      
      // Check if shares are zeroed out (meaning it was corrupted by old settlement logic)
      final allZeros = shares.values.every((v) => (v as num).toDouble().abs() < 0.01);
      
      if (allZeros && shares.isNotEmpty) {
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final participants = List<String>.from(data['participants'] ?? const []);
        if (participants.isNotEmpty) {
          final equalShare = amount / participants.length;
          final restoredShares = {for (var uid in participants) uid: equalShare};
          await updateExpenseShares(doc.id, restoredShares);
          print("✅ Restored shares for expense ${doc.id}");
        }
      }
    }
    print("🎉 restoreSettledShares complete!");
  }

  /// Marks ALL expenses in a group as settled and zeros out shares.
  /// Call this when the group becomes fully settled.
  Future<void> settleAllExpensesInGroup(String groupId) async {
    final snapshot = await _db
        .collection('expenses')
        .where('groupId', isEqualTo: groupId)
        .get();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final currentStatus = (data['status'] as String? ?? '').toLowerCase().trim();
      if (currentStatus == 'settled') continue; // skip already settled

      await doc.reference.update({
        'status': 'settled',
      });
    }
  }



  // REACTIONS: groups/{groupId}/expenses/{id}/reactions/{uid}

  Future<void> toggleReaction({
    required String groupId,
    required String expenseId,
    required String uid,
    required String emoji,
  }) async {
    final ref = _db
        .collection('expenses')
        .doc(expenseId)
        .collection('reactions')
        .doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'emoji': emoji,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      final current = snap.data()?['emoji'] as String?;
      if (current == emoji) {
        await ref.delete();
      } else {
        await ref.update({'emoji': emoji});
      }
    }
  }

  Stream<String?> streamUserReaction({
    required String groupId,
    required String expenseId,
    required String uid,
  }) {
    return _db
        .collection('expenses')
        .doc(expenseId)
        .collection('reactions')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.data()?['emoji'] as String?);
  }

  Stream<Map<String, String>> streamReactions(String groupId, String expenseId) {
    return _db
        .collection('expenses')
        .doc(expenseId)
        .collection('reactions')
        .snapshots()
        .map((snap) {
          final map = <String, String>{};
          for (var doc in snap.docs) {
            map[doc.id] = doc.data()['emoji'] as String;
          }
          return map;
        });
  }

  // HELPER: Fetch tokens and send notification
  Future<void> _notifyGroupMembers({
    required String groupId,
    required String title,
    required String body,
    required String excludeUid,
  }) async {
    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final memberUids = List<String>.from(
        groupDoc.data()?['members'] ?? [],
      ).where((uid) => uid != excludeUid).toList();

      if (memberUids.isEmpty) return;

      final users = await getUsers(memberUids);
      final tokens = users
          .map((u) => u.fcmToken)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();

      if (tokens.isNotEmpty) {
        Future.microtask(() async {
          try {
            await NotificationService().sendGroupNotification(
              groupId: groupId,
              title: title,
              body: body,
              excludeUid: excludeUid,
              targetTokens: tokens,
            );
          } catch (e) {
            debugPrint("Notification failed: $e");
          }
        });
      }
    } catch (e) {
      // Don't crash main flow
    }
  }

  // Helper: convert currency code to symbol
  String _getSymbol(String code) {
    if (code == 'USD') return r'$';
    if (code == 'EUR') return '€';
    if (code == 'GBP') return '£';
    return '₹';
  }
}
