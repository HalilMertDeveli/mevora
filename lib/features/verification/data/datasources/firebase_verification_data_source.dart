import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';

class FirebaseVerificationDataSource {
  FirebaseVerificationDataSource({
    FirebaseFirestore? firestore,
    BackendCallable? backend,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _backend = backend;

  final FirebaseFirestore _firestore;
  final BackendCallable? _backend;

  Stream<ProfileVerification> watchVerification(String uid) {
    return _firestore
        .doc('users/$uid/verification/sumsub')
        .snapshots()
        .map(_fromSnapshot);
  }

  Future<String> createAccessToken() async {
    final backend = _backend;
    if (backend == null) {
      throw StateError('Backend callable unavailable');
    }
    final data = await backend.invoke('createSumsubAccessToken');
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw FormatException('Missing Sumsub access token');
    }
    return token;
  }

  ProfileVerification _fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (!snap.exists) {
      return ProfileVerification.notStarted;
    }
    final data = snap.data() ?? const {};
    return ProfileVerification(
      status: profileVerificationStatusFromFirestore(data['verificationStatus']),
      verificationLevel: data['verificationLevel'] as String?,
      sumsubApplicantId: data['sumsubApplicantId'] as String?,
      verificationUpdatedAt: firestoreDate(data['verificationUpdatedAt']),
      verifiedAt: firestoreDate(data['verifiedAt']),
      verificationAttemptCount: firestoreInt(
        data['verificationAttemptCount'],
        0,
      ),
      lastVerificationAttemptAt: firestoreDate(
        data['lastVerificationAttemptAt'],
      ),
    );
  }
}
