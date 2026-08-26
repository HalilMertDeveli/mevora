import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

/// Reads `users/{uid}/subscription/current` (Admin/CF written only).
class FirestoreSubscriptionRepository implements SubscriptionRepository {
  FirestoreSubscriptionRepository({
    required AuthUidSource uidSource,
    FirebaseFirestore? firestore,
  }) : _uidSource = uidSource,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthUidSource _uidSource;
  final FirebaseFirestore _firestore;

  @override
  Stream<PremiumStatus> watch() {
    return _uidSource.watchUid().asyncExpand((uid) {
      if (uid == null || uid.isEmpty) {
        return Stream.value(const PremiumStatus());
      }
      return _firestore
          .doc(FirestorePaths.subscriptionCurrent(uid))
          .snapshots()
          .map(_fromSnap);
    });
  }

  PremiumStatus _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) {
      return const PremiumStatus();
    }
    final data = snap.data() ?? const <String, dynamic>{};
    if (data['isPremium'] != true) {
      return const PremiumStatus();
    }
    final expiresRaw = data['expiresAt'];
    DateTime? expiresAt;
    if (expiresRaw is Timestamp) {
      expiresAt = expiresRaw.toDate();
      if (expiresAt.isBefore(DateTime.now())) {
        return const PremiumStatus();
      }
    }
    return PremiumStatus(isPremium: true, expiresAt: expiresAt);
  }
}
