import 'package:cloud_firestore/cloud_firestore.dart';

class Group {
  final String id;
  final String name;
  final String code;
  final String ownerId; // Mapped to 'createdBy' in Firestore
  final DateTime createdAt;

  Group({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerId,
    required this.createdAt,
  });

  factory Group.fromMap(String id, Map<String, dynamic> data) {
    return Group(
      id: id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      ownerId: data['createdBy'] as String? ?? '', // Changed from ownerId
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'code': code,
      'createdBy': ownerId,
      'createdAt': createdAt,
    };
  }
}

