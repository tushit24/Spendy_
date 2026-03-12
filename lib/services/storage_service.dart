import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadProfileImage(String uid, File file) async {
    final ref = _storage.ref().child('profile_images/$uid.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }
}
