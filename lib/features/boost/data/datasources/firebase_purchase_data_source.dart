import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';
import 'package:mevora/features/boost/domain/services/boost_activation_service.dart';

/// Reads owner boosts and calls verifyBoostPurchase. Never writes status,
/// expiresAt, verifiedAt, purchaseId, transactionId, or userId from the client.
abstract class PurchaseRemoteDataSource {
  Future<Boost> verifyPurchase({
    required String userId,
    required StoreTransaction transaction,
  });

  Future<Boost?> loadActiveBoost(String userId);
}

class FirebasePurchaseDataSource implements PurchaseRemoteDataSource {
  FirebasePurchaseDataSource({
    required BackendCallable backend,
    FirebaseFirestore? firestore,
    AppLogger? logger,
    BoostActivationService activation = const BoostActivationService(),
    DateTime Function()? clock,
  }) : _backend = backend,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _logger = logger,
       _activation = activation,
       _clock = clock ?? DateTime.now;

  final BackendCallable _backend;
  final FirebaseFirestore _firestore;
  final AppLogger? _logger;
  final BoostActivationService _activation;
  final DateTime Function() _clock;

  Future<Boost> verifyPurchase({
    required String userId,
    required StoreTransaction transaction,
  }) async {
    try {
      final data = await _backend.invoke('verifyBoostPurchase', {
        'platform': transaction.platform.name,
        'productId': transaction.productId,
        'transactionId': transaction.transactionId,
        if (transaction.purchaseToken != null)
          'purchaseToken': transaction.purchaseToken,
        if (transaction.signedTransaction != null)
          'signedTransaction': transaction.signedTransaction,
        if (transaction.receiptData != null)
          'receiptData': transaction.receiptData,
      });
      final boost = _boostFromMap(data['boost']);
      if (boost == null) {
        throw const PurchaseException(
          AppStrings.boostVerificationFailed,
          kind: PurchaseErrorKind.verificationFailed,
        );
      }
      if (data['alreadyActive'] == true) {
        throw const PurchaseException(
          AppStrings.boostAlreadyActive,
          kind: PurchaseErrorKind.alreadyActive,
        );
      }
      return boost;
    } on PurchaseException {
      rethrow;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapCallable(error), stackTrace);
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Boost verification call failed',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(
        const PurchaseException(
          AppStrings.boostNetworkError,
          kind: PurchaseErrorKind.network,
        ),
        stackTrace,
      );
    }
  }

  Future<Boost?> loadActiveBoost(String userId) async {
    try {
      final snap = await _firestore
          .collection(FirestorePaths.userBoosts(userId))
          .get();
      final boosts = snap.docs
          .map((doc) => _boostFromDoc(userId, doc.id, doc.data()))
          .whereType<Boost>();
      return _activation.activeBoost(boosts, _clock());
    } on FirebaseException catch (error, stackTrace) {
      _logger?.warning(
        'Active boost read failed',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(
        const PurchaseException(
          AppStrings.boostNetworkError,
          kind: PurchaseErrorKind.network,
        ),
        stackTrace,
      );
    }
  }

  Boost? _boostFromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final data = Map<String, dynamic>.from(raw);
    final boostId = data['boostId'] as String?;
    final userId = data['userId'] as String?;
    if (boostId == null || userId == null) {
      return null;
    }
    return _boostFromDoc(userId, boostId, data);
  }

  Boost? _boostFromDoc(String userId, String boostId, Map<String, dynamic> data) {
    final status = _statusOf(data['status'] as String?);
    final createdAt = _dateOf(data['createdAt']) ?? _clock();
    return Boost(
      boostId: (data['boostId'] as String?) ?? boostId,
      userId: (data['userId'] as String?) ?? userId,
      productId: (data['productId'] as String?) ?? '',
      purchaseId: (data['purchaseId'] as String?) ?? '',
      status: status,
      createdAt: createdAt,
      startedAt: _dateOf(data['startedAt']),
      expiresAt: _dateOf(data['expiresAt']),
    );
  }

  DateTime? _dateOf(Object? value) {
    final fromFs = firestoreDate(value);
    if (fromFs != null) {
      return fromFs;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  BoostStatus _statusOf(String? raw) {
    return switch (raw) {
      'active' => BoostStatus.active,
      'expired' => BoostStatus.expired,
      'cancelled' => BoostStatus.cancelled,
      _ => BoostStatus.pending,
    };
  }

  PurchaseException _mapCallable(FirebaseFunctionsException error) {
    final details = error.details;
    final reason = details is Map ? details['reason'] as String? : null;
    if (reason == 'already-active' || error.code == 'failed-precondition') {
      return const PurchaseException(
        AppStrings.boostAlreadyActive,
        kind: PurchaseErrorKind.alreadyActive,
      );
    }
    if (reason == 'already-processed' || error.code == 'already-exists') {
      return const PurchaseException(
        AppStrings.boostAlreadyProcessed,
        kind: PurchaseErrorKind.alreadyProcessed,
      );
    }
    if (error.code == 'unavailable') {
      return const PurchaseException(
        AppStrings.boostStoreDown,
        kind: PurchaseErrorKind.storeDown,
      );
    }
    if (error.code == 'resource-exhausted' ||
        error.code == 'deadline-exceeded') {
      return const PurchaseException(
        AppStrings.boostNetworkError,
        kind: PurchaseErrorKind.network,
      );
    }
    return const PurchaseException(
      AppStrings.boostVerificationFailed,
      kind: PurchaseErrorKind.verificationFailed,
    );
  }
}
