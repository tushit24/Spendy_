import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';

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
    return _db.collection('users').doc(uid).snapshots().map(
          (snap) => AppUser.fromMap(snap.id, snap.data() ?? {}),
        );
  }

  Future<void> updateUserName(String uid, String name) {
    return _db.collection('users').doc(uid).update({'name': name});
  }

  Future<void> updateUserPhotoUrl(String uid, String url) {
    return _db.collection('users').doc(uid).update({'photoUrl': url});
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
          (snap) => snap.docs
              .map((d) => Group.fromMap(d.id, d.data()))
              .toList(),
        );
  }
  // GROUPS logic moved to GroupService.dart
  // Keeping streamUserGroups for backward compatibility if needed temporarily, 
  // but recommended to use GroupService.




  // EXPENSES

  Future<void> addExpense(Expense expense) async {
    final ref = _db.collection('expenses').doc();
    await ref.set(expense.toMap()..['createdAt'] = FieldValue.serverTimestamp());
  }

  Stream<List<Expense>> streamUserExpenses(String uid) {
    return _db
        .collection('expenses')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Expense.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<List<Expense>> streamFilteredExpenses({
    required String uid,
    String? groupId,
    String? userFilterUid,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('expenses');

    if (groupId != null && groupId.isNotEmpty) {
      q = q.where('groupId', isEqualTo: groupId);
    }

    // If filtering by another user, Firestore cannot OR two conditions directly.
    // We fall back to in-memory filter on a broader query.
    if (userFilterUid != null && userFilterUid.isNotEmpty) {
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

    q = q.where('participants', arrayContains: uid);

    return q
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Expense.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<void> updateExpenseStatus(String expenseId, String status) {
    return _db
        .collection('expenses')
        .doc(expenseId)
        .update({'status': status});
  }

  // REACTIONS: expenses/{id}/reactions/{uid}

  Future<void> toggleReaction({
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
      await ref.set(
        {
          'emoji': emoji,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
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

  Stream<Map<String, String>> streamReactions(String expenseId) {
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
}

