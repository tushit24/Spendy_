import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final DateTime createdAt;
  final String? fcmToken;
  final bool requestDailyReminder;
  final bool requestMonthlyReminder;
  final String currency;
  final String? upiId;

  final List<String> joinedGroups;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.createdAt,
    this.photoUrl,
    this.fcmToken,
    this.requestDailyReminder = true,
    this.requestMonthlyReminder = true,
    this.currency = 'INR',
    this.joinedGroups = const [],
    this.upiId,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      fcmToken: data['fcmToken'] as String?,
      requestDailyReminder: data['requestDailyReminder'] as bool? ?? true,
      requestMonthlyReminder: data['requestMonthlyReminder'] as bool? ?? true,
      currency: data['currency'] as String? ?? 'INR',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      joinedGroups: List<String>.from(data['joinedGroups'] ?? []),
      upiId: data['upiId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'fcmToken': fcmToken,
      'requestDailyReminder': requestDailyReminder,
      'requestMonthlyReminder': requestMonthlyReminder,
      'currency': currency,
      'createdAt': createdAt,
      'joinedGroups': joinedGroups,
      'upiId': upiId,
    };
  }
}
