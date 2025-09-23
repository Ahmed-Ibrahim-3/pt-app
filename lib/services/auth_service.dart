import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firestore_sync.dart';

class AuthService {
  AuthService(this._auth, this.ref);
  final FirebaseAuth _auth;
  final Ref ref;

  Future<UserCredential> createAccount(String email, String password, {String? displayName}) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    if ((displayName ?? '').isNotEmpty) {
      await cred.user?.updateDisplayName(displayName!);
    }
    await ref.read(firestoreSyncProvider).refreshFromCloud();
    return cred;
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    await ref.read(firestoreSyncProvider).refreshFromCloud();
    return cred;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await ref.read(firestoreSyncProvider).onAuthChange(previousUid: null, currentUid: null);
  }

  User? get currentUser => _auth.currentUser;
}
