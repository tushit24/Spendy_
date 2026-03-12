import 'package:cloud_firestore/cloud_firestore.dart';

class Group {
  final String id;
  final String name;
  final String code;
  final String ownerId;
  final List<String> members;
  final DateTime createdAt;

  Group({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerId,
    this.members = const [],
    required this.createdAt,
  });

  factory Group.fromMap(String id, Map<String, dynamic> data) {
    return Group(
      id: id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      members: List<String>.from(data['members'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'code': code,
      'ownerId': ownerId,
      'members': members,
      'createdAt': createdAt,
    };
  }
}
