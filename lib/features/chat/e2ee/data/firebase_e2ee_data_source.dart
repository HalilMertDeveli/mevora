import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';
import 'package:mevora/features/chat/e2ee/models/e2ee_identity.dart';

/// Publishes public keys only. Private keys never touch Firestore.
class FirebaseE2eeDataSource {
  FirebaseE2eeDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _identityDoc(String uid) {
    return _firestore
        .doc('${FirestorePaths.user(uid)}/crypto/${E2eeConstants.firestoreIdentityDoc}');
  }

  Future<void> publishIdentity({
    required String uid,
    required E2eeIdentity identity,
  }) async {
    await _identityDoc(uid).set({
      'publicKey': identity.publicKeyBase64,
      'algorithm': identity.algorithm,
      'keyVersion': identity.keyVersion,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<E2eeIdentity?> fetchIdentity(String uid) async {
    final snap = await _identityDoc(uid).get();
    final data = snap.data();
    if (data == null) {
      return null;
    }
    final publicKey = data['publicKey'] as String?;
    if (publicKey == null || publicKey.isEmpty) {
      return null;
    }
    return E2eeIdentity(
      publicKeyBase64: publicKey,
      keyVersion: (data['keyVersion'] as num?)?.toInt() ??
          E2eeConstants.currentKeyVersion,
      algorithm: (data['algorithm'] as String?) ?? E2eeConstants.algorithm,
    );
  }
}
