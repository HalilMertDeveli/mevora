import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification_session.dart';
import 'package:mevora/features/verification/domain/entities/legacy_verification_bridge.dart';

/// The provider boundary on the client.
///
/// Everything provider-shaped stops here: the document id, the legacy field
/// names, the callable name and the shape of its response. Above this class
/// the app sees only [IdentityVerification] and [IdentityVerificationSession].
class FirebaseVerificationDataSource {
  FirebaseVerificationDataSource({
    FirebaseFirestore? firestore,
    BackendCallable? backend,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _backend = backend;

  final FirebaseFirestore _firestore;
  final BackendCallable? _backend;

  /// The provider-neutral verification document.
  static const identityDocId = 'identity';

  /// The callable that creates a session for the signed-in user.
  ///
  /// Still the Sumsub-era callable: Phase 2 moves the *domain* off the
  /// provider, and Phase 3 replaces the backend behind this one name. The
  /// client contract does not change when it does.
  static const createSessionCallable = 'createSumsubAccessToken';

  /// Watches the neutral document, falling back to the legacy one.
  ///
  /// Both are read because a user verified before the migration would
  /// otherwise silently lose their badge. The neutral document wins whenever
  /// it exists, so the fallback retires itself as users re-verify. Production
  /// currently holds neither (`docs/DIDIT_MIGRATION_PHASE1.md` STEP 14).
  Stream<IdentityVerification> watchVerification(String uid) {
    return _firestore
        .doc('users/$uid/verification/$identityDocId')
        .snapshots()
        .asyncMap((snap) async {
          if (snap.exists) {
            return _fromIdentitySnapshot(snap);
          }
          final legacy = await _firestore
              .doc('users/$uid/verification/${LegacyVerificationFields.docId}')
              .get();
          return _fromLegacySnapshot(legacy);
        });
  }

  Future<IdentityVerificationSession> startVerificationSession() async {
    final backend = _backend;
    if (backend == null) {
      throw StateError('Backend callable unavailable');
    }
    final data = await backend.invoke(createSessionCallable);

    // A native-SDK provider returns a launch token; a hosted-flow provider
    // returns a URL. Accept either so Phase 3 can switch the backend without
    // touching anything above this line.
    final token = (data['token'] ?? data['sessionToken']) as String?;
    final url = data['url'] as String?;
    final sessionId =
        (data['sessionId'] ?? data['providerSessionId']) as String?;

    final session = IdentityVerificationSession(
      providerSessionId: sessionId ?? '',
      launchToken: token,
      launchUrl: url,
    );
    if (!session.canLaunch) {
      throw const FormatException('Verification session cannot be launched');
    }
    return session;
  }

  IdentityVerification _fromIdentitySnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data() ?? const <String, dynamic>{};
    return IdentityVerification(
      status: identityVerificationStatusFromFirestore(data['status']),
      provider: IdentityVerificationProvider.fromWire(data['provider']),
      providerSessionId: data['providerSessionId'] as String?,
      createdAt: firestoreDate(data['createdAt']),
      updatedAt: firestoreDate(data['updatedAt']),
      verifiedAt: firestoreDate(data['verifiedAt']),
      reason: IdentityVerificationReason.fromWire(data['reason']),
      attemptCount: firestoreInt(data['attemptCount'], 0),
      lastAttemptAt: firestoreDate(data['lastAttemptAt']),
      schemaVersion: data['schemaVersion'] == null
          ? null
          : firestoreInt(data['schemaVersion'], 0),
    );
  }

  IdentityVerification _fromLegacySnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (!snap.exists) {
      return IdentityVerification.notStarted;
    }
    final data = snap.data() ?? const <String, dynamic>{};
    return IdentityVerification(
      status: identityStatusFromLegacyWire(
        data[LegacyVerificationFields.status],
      ),
      provider: IdentityVerificationProvider.sumsub,
      providerSessionId:
          data[LegacyVerificationFields.providerSessionId] as String?,
      updatedAt: firestoreDate(data[LegacyVerificationFields.updatedAt]),
      verifiedAt: firestoreDate(data[LegacyVerificationFields.verifiedAt]),
      attemptCount: firestoreInt(data[LegacyVerificationFields.attemptCount], 0),
      lastAttemptAt: firestoreDate(data[LegacyVerificationFields.lastAttemptAt]),
    );
  }
}
