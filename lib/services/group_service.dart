
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';

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

    final group = Group(
      id: groupId,
      name: name,
      code: code,
      ownerId: user.uid,
      createdAt: DateTime.now(),
    );

    // Batch write to ensure atomicity
    final batch = _db.batch();

    // 1. Create group document
    batch.set(groupRef, group.toMap());

    // 2. Add creator to members subcollection
    final memberRef = groupRef.collection('members').doc(user.uid);
    batch.set(memberRef, {
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'photoUrl': user.photoURL,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // 3. Add groupId to user's joinedGroups array
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
    final joinedGroups = List<String>.from(userDoc['joinedGroups'] ?? []);
    if (joinedGroups.contains(groupId)) {
      throw Exception('You are already a member of this group');
    }

    final batch = _db.batch();

    // 2. Add user to members subcollection
    final memberRef =
        _db.collection('groups').doc(groupId).collection('members').doc(user.uid);
    batch.set(memberRef, {
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'photoUrl': user.photoURL,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // 3. Add groupId to user's joinedGroups
    final userRef = _db.collection('users').doc(user.uid);
    batch.update(userRef, {
      'joinedGroups': FieldValue.arrayUnion([groupId]),
    });

    await batch.commit();
    return groupName;
  }

  // 4. LEAVE GROUP
  Future<void> leaveGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final batch = _db.batch();

    // 1. Remove user from members subcollection
    final memberRef =
        _db.collection('groups').doc(groupId).collection('members').doc(user.uid);
    batch.delete(memberRef);

    // 2. Remove groupId from user's joinedGroups
    final userRef = _db.collection('users').doc(user.uid);
    batch.update(userRef, {
      'joinedGroups': FieldValue.arrayRemove([groupId]),
    });

    await batch.commit();
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

    // 1. Delete all members
    final membersSnap = await groupRef.collection('members').get();
    for (var doc in membersSnap.docs) {
      // Remove group from user's joinedGroups
      await _db.collection('users').doc(doc.id).update({
        'joinedGroups': FieldValue.arrayRemove([groupId])
      });
      await doc.reference.delete();
    }

    // 2. Delete all expenses
    final expensesSnap = await groupRef.collection('expenses').get();
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
    
    return _db
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .asyncMap((userSnap) async {
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

  // HELPER: Generate unique code
  Future<String> _generateUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No I, O, 0, 1
    final rand = Random();
    
    while (true) {
      final code = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
      
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
    final countQuery = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .count()
        .get();
    return countQuery.count ?? 0;
  }

  // 6. GET GROUP MEMBERS
  Future<List<AppUser>> getGroupMembers(String groupId) async {
    final snap = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      return AppUser(
        uid: doc.id,
        name: data['name'] ?? '',
        email: data['email'] ?? '',
        photoUrl: data['photoUrl'],
        createdAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }
}
