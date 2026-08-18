import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';

class FirebaseAuthUidSource implements AuthUidSource {
  FirebaseAuthUidSource({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  @override
  String? get currentUid => _firebaseAuth.currentUser?.uid;

  @override
  Stream<String?> watchUid() {
    return _firebaseAuth.authStateChanges().map((user) => user?.uid);
  }
}
