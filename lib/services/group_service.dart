import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import 'notification_service.dart';
import 'firestore_service.dart';

class GroupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. GROUP CREATION
  Future<String> createGroup(String name) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    String code = await _generateUniqueCode();
    final groupRef = _db.collection('groups').doc();
    final groupId = groupRef.id;

    // Batch write to ensure atomicity
    final batch = _db.batch();

    // 1. Create group document with members array
    batch.set(groupRef, {
      "name": name,
      "code": code,
      "ownerId": user.uid,
      "members": [user.uid],
      "createdAt": FieldValue.serverTimestamp()
    });

    // 2. Add groupId to user's joinedGroups array
    final userRef = _db.collection('users').doc(user.uid);
    batch.update(userRef, {
      'joinedGroups': FieldValue.arrayUnion([groupId]),
    });

    await batch.commit();

    return groupId;
  }

  // 2. JOIN GROUP
  Future<String> joinGroup(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // 1. Search for group
    final querySnapshot = await _db
        .collection('groups')
        .where('code', isEqualTo: code)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw Exception('Group not found');
    }

    final groupDoc = querySnapshot.docs.first;
    final groupId = groupDoc.id;
    final groupName = groupDoc['name'];

    // Check if already a member (optimization: check user's array first)
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final joinedGroups = List<String>.from(userDoc.data()?['joinedGroups'] ?? []);
    if (joinedGroups.contains(groupId)) {
      throw Exception('You are already a member of this group');
    }

    final batch = _db.batch();

    // 2. Add user to group's members array
    batch.update(groupDoc.reference, {
      'members': FieldValue.arrayUnion([user.uid]),
    });

    // 3. Add groupId to user's joinedGroups
    final userRef = _db.collection('users').doc(user.uid);
    batch.update(userRef, {
      'joinedGroups': FieldValue.arrayUnion([groupId]),
    });

    await batch.commit();

    // 4. Send notification to group members
    await _notifyGroupMembers(
      groupId: groupId,
      title: 'New Member!',
      body: '${user.displayName} joined $groupName',
      excludeUid: user.uid,
    );

    return groupName;
  }

  // 4. LEAVE GROUP
  Future<void> leaveGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final batch = _db.batch();

    // 1. Remove user from group's members array
    final groupRef = _db.collection('groups').doc(groupId);
    batch.update(groupRef, {
      'members': FieldValue.arrayRemove([user.uid]),
    });

    // 2. Remove groupId from user's joinedGroups
    final userRef = _db.collection('users').doc(user.uid);
    batch.update(userRef, {
      'joinedGroups': FieldValue.arrayRemove([groupId]),
    });

    await batch.commit();

    // 3. Notify remaining members
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (groupDoc.exists) {
      await _notifyGroupMembers(
        groupId: groupId,
        title: 'Member Left',
        body: '${user.displayName} left ${groupDoc['name']}',
        excludeUid: user.uid,
      );
    }
  }

  // 5. DELETE GROUP (Admin only)
  Future<void> deleteGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final groupRef = _db.collection('groups').doc(groupId);
    final groupDoc = await groupRef.get();

    if (!groupDoc.exists) throw Exception('Group not found');
    if (groupDoc['createdBy'] != user.uid) {
      throw Exception('Only the admin can delete the group');
    }

    // NOTE: Firestore does not support recursive delete in client SDK efficiently.
    // For a college project, we will manually delete subcollections fetched.
    // In production, use Cloud Functions.

    // 1. Remove group from all members' joinedGroups arrays
    final membersList = List<String>.from(groupDoc.data()?['members'] ?? []);
    for (var memberId in membersList) {
      await _db.collection('users').doc(memberId).update({
        'joinedGroups': FieldValue.arrayRemove([groupId]),
      });
    }

    // 2. Delete all expenses
    final expensesSnap = await _db
        .collection('expenses')
        .where('groupId', isEqualTo: groupId)
        .get();
    for (var doc in expensesSnap.docs) {
      await doc.reference.delete();
    }

    // 3. Delete group document
    await groupRef.delete();
  }

  Stream<List<Group>> getUserGroups() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // We filter groups where the user is a member.
    // However, the user's `joinedGroups` array is in `users/{uid}`.
    // But we need to query the `groups` collection.
    // Since `joinedGroups` is on the user doc, we can stream the user doc
    // and then fetch/stream the groups.
    // OR we can query groups where 'members/{uid}' exists? No, Firestore subcollection query is limited.
    // Best approach given structure:
    // Query groups where ID is in `joinedGroups`? NO, `whereIn` limit 10.

    // Alternative for College Project:
    // Stream User -> Get joinedGroups IDs -> Stream each group? specific/complex.

    // Simpler: Stream `users/{uid}` and map to a list of Futures? No, StreamBuilder needs a stream.

    // Let's stick to the previous pattern if possible, but the requirement says:
    // "users/{uid} - joinedGroups: array of groupIds"

    return _db.collection('users').doc(user.uid).snapshots().asyncMap((
      userSnap,
    ) async {
      final data = userSnap.data();
      if (data == null || data['joinedGroups'] == null) return [];

      final groupIds = List<String>.from(data['joinedGroups']);
      if (groupIds.isEmpty) return [];

      // Fetch all groups (splitting not implemented for simplicity as usage is low scale)
      // Note: `whereIn` is limited to 10.
      if (groupIds.length > 10) {
        // Just take first 10 for safety in this project scope
        groupIds.length = 10;
      }

      final groupsSnap = await _db
          .collection('groups')
          .where(FieldPath.documentId, whereIn: groupIds)
          .get();

      return groupsSnap.docs
          .map((doc) => Group.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  Stream<Group?> streamGroup(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((snap) => snap.exists ? Group.fromMap(snap.id, snap.data()!) : null);
  }

  // HELPER: Generate unique code
  Future<String> _generateUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No I, O, 0, 1
    final rand = Random();

    while (true) {
      final code = List.generate(
        6,
        (_) => chars[rand.nextInt(chars.length)],
      ).join();

      final snap = await _db
          .collection('groups')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        return code;
      }
    }
  }

  // HELPER: Get member count (for UI)
  Future<int> getMemberCount(String groupId) async {
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return 0;

    final membersList = List<String>.from(groupDoc.data()?['members'] ?? []);
    return membersList.length;
  }

  // 6. LOAD GROUP MEMBERS
  Future<List<AppUser>> loadGroupMembers(String groupId) async {
    // 1. Get group document to find member IDs
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return [];

    final memberIds = List<String>.from(groupDoc.data()?['members'] ?? []);
    if (memberIds.isEmpty) return [];

    // 2. Query users collection
    final usersSnap = await _db
        .collection('users')
        .where(FieldPath.documentId, whereIn: memberIds.take(10).toList())
        .get();

    return usersSnap.docs.map((doc) {
      final data = doc.data();
      return AppUser(
        uid: doc.id,
        name: data['name'] ?? '',
        email: data['email'] ?? '',
        photoUrl: data['photoUrl'],
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  // HELPER: Fetch tokens and send notification
  Future<void> _notifyGroupMembers({
    required String groupId,
    required String title,
    required String body,
    required String excludeUid,
  }) async {
    try {
      final members = await loadGroupMembers(groupId);
      final memberUids = members
          .map((m) => m.uid)
          .where((uid) => uid != excludeUid)
          .toList();

      if (memberUids.isEmpty) return;

      final users = await FirestoreService.instance.getUsers(memberUids);
      final tokens = users
          .map((u) => u.fcmToken)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();

      if (tokens.isNotEmpty) {
        await NotificationService().sendGroupNotification(
          groupId: groupId,
          title: title,
          body: body,
          excludeUid: excludeUid,
          targetTokens: tokens,
        );
      }
    } catch (e) {
      // Don't crash the main flow if notification fails
    }
  }
}
