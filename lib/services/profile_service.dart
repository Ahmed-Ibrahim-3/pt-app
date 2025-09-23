import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_settings.dart';

class ProfileService {
  final FirebaseFirestore _db;
  ProfileService(this._db);

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  Stream<UserSettings> watchSettings(String uid) =>
      _doc(uid).snapshots().map((s) => UserSettings.fromMap(s.data()));

  Future<UserSettings> fetchSettings(String uid) async {
    final s = await _doc(uid).get();
    return UserSettings.fromMap(s.data());
  }

  Future<void> saveSettings(String uid, UserSettings settings) async {
    await _doc(uid).set(settings.toMap(), SetOptions(merge: true));
  }

  Future<void> upsertUserProfile({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }
}
