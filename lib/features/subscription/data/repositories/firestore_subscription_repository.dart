import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/features/subscription/domain/subscription_entitlement_policy.dart';

/// Raw `users/{uid}/subscription/current` documents for one user. Null means
/// the document does not exist.
typedef SubscriptionDocumentStream =
    Stream<Map<String, dynamic>?> Function(String uid);

/// Reads `users/{uid}/subscription/current` (Admin/CF written only).
class FirestoreSubscriptionRepository implements SubscriptionRepository {
  FirestoreSubscriptionRepository({
    required AuthUidSource uidSource,
    FirebaseFirestore? firestore,
    DateTime Function()? clock,
    SubscriptionDocumentStream? documentStream,
  }) : _uidSource = uidSource,
       _firestore = firestore,
       _clock = clock ?? DateTime.now,
       _documentStream = documentStream;

  final AuthUidSource _uidSource;
  final FirebaseFirestore? _firestore;
  final DateTime Function() _clock;
  final SubscriptionDocumentStream? _documentStream;

  /// Switches to the signed-in user's document, dropping the previous one.
  ///
  /// Deliberately not `asyncExpand`: that waits for the inner stream to
  /// finish before moving on, and a document stream never finishes — so an
  /// account switch would keep serving the previous account's entitlement.
  @override
  Stream<PremiumStatus> watch() {
    late final StreamController<PremiumStatus> controller;
    StreamSubscription<String?>? uidSubscription;
    StreamSubscription<PremiumStatus>? documentSubscription;
    var pending = Future<void>.value();

    Future<void> switchTo(String? uid) async {
      await documentSubscription?.cancel();
      documentSubscription = null;
      if (controller.isClosed) {
        return;
      }
      // Drop the previous account's entitlement before the next snapshot
      // lands, so a sign-out or switch never leaves Premium on screen.
      controller.add(PremiumStatus.free);
      if (uid == null || uid.isEmpty) {
        return;
      }
      documentSubscription = (_documentStream ?? _firestoreDocuments)(uid)
          .map(_evaluate)
          .listen(
            controller.add,
            onError: (Object _) => controller.add(PremiumStatus.free),
          );
    }

    controller = StreamController<PremiumStatus>(
      onListen: () {
        uidSubscription = _uidSource.watchUid().distinct().listen((uid) {
          // Serialised so two quick sign-ins cannot interleave their
          // subscriptions and leave the wrong document attached.
          pending = pending.then((_) => switchTo(uid));
        });
      },
      onCancel: () async {
        await uidSubscription?.cancel();
        await documentSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<Map<String, dynamic>?> _firestoreDocuments(String uid) {
    return (_firestore ?? FirebaseFirestore.instance)
        .doc(FirestorePaths.subscriptionCurrent(uid))
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  PremiumStatus _evaluate(Map<String, dynamic>? data) {
    return SubscriptionEntitlementPolicy.evaluate(
      data,
      now: _clock(),
      dateParser: parseSubscriptionDate,
    );
  }

  /// Firestore hands back `Timestamp`; tests and fakes hand back `DateTime`.
  static DateTime? parseSubscriptionDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
