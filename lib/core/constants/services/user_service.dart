import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final _db = FirebaseFirestore.instance;

  Future<void> upsertUserProfile({
    required String uid,
    required String email,
    required String role,
    String? name,
    String? phone,
    Map<String, dynamic>? extra, // for driver fields etc.
  }) async {
    final data = <String, dynamic>{
      'email': email,
      'role': role,
      'name': name,
      'phone': phone,
      'updatedAt': FieldValue.serverTimestamp(),
      // only set createdAt the first time
      'createdAt': FieldValue.serverTimestamp(),
      ...?extra,
    };

    // Remove nulls so you don’t overwrite with null
    data.removeWhere((k, v) => v == null);

    await _db
        .collection('users')
        .doc(uid)
        .set(
          data,
          SetOptions(merge: true), // IMPORTANT
        );
  }
}
