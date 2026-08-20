import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_credit_result.dart';
import 'package:mevora/features/boost/domain/entities/boost_history_entry.dart';
import 'package:mevora/features/boost/domain/entities/boost_pack.dart';
import 'package:mevora/features/boost/domain/entities/boost_wallet.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';
import 'package:mevora/features/boost/domain/services/boost_activation_service.dart';

/// Reads owner boosts/wallet and calls verify/activate. Never writes status,
/// expiresAt, verifiedAt, purchaseId, transactionId, balance, or userId.
abstract class PurchaseRemoteDataSource {
  Future<BoostCreditResult> verifyPurchase({
    required String userId,
    required StoreTransaction transaction,
  });

  Future<Boost> activateBoost(String userId);

  Future<Boost?> loadActiveBoost(String userId);

  Future<BoostWallet> loadWallet(String userId);

  Future<List<BoostHistoryEntry>> loadHistory(String userId);

  Future<List<BoostPack>> loadCatalog();
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

  @override
  Future<BoostCreditResult> verifyPurchase({
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
      if (data['alreadyActive'] == true) {
        throw const PurchaseException(
          AppStrings.boostAlreadyActive,
          kind: PurchaseErrorKind.alreadyActive,
        );
      }
      final purchase = _mapOf(data['purchase']);
      final wallet = _mapOf(data['wallet']);
      final purchaseId = purchase?['purchaseId'] as String? ??
          '${transaction.platform.name}_${transaction.transactionId}';
      return BoostCreditResult(
        purchaseId: purchaseId,
        productId:
            purchase?['productId'] as String? ?? transaction.productId,
        boostCount: _intOf(purchase?['boostCount'], fallback: 1),
        balance: _intOf(wallet?['balance']),
        alreadyProcessed: data['alreadyProcessed'] == true,
      );
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

  @override
  Future<Boost> activateBoost(String userId) async {
    try {
      final data = await _backend.invoke('activateBoost', <String, dynamic>{});
      final boost = _boostFromMap(data['boost']);
      if (boost == null) {
        throw const PurchaseException(
          AppStrings.boostVerificationFailed,
          kind: PurchaseErrorKind.verificationFailed,
        );
      }
      return boost;
    } on PurchaseException {
      rethrow;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapCallable(error), stackTrace);
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Boost activate call failed',
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

  @override
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

  @override
  Future<BoostWallet> loadWallet(String userId) async {
    try {
      final snap = await _firestore
          .doc(FirestorePaths.userBoostWallet(userId))
          .get();
      final data = snap.data();
      return BoostWallet(
        balance: _intOf(data?['balance']),
        updatedAt: _dateOf(data?['updatedAt']),
      );
    } on FirebaseException catch (error, stackTrace) {
      _logger?.warning(
        'Boost wallet read failed',
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

  @override
  Future<List<BoostHistoryEntry>> loadHistory(String userId) async {
    try {
      final purchases = await _firestore
          .collection(FirestorePaths.purchases)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      final boosts = await _firestore
          .collection(FirestorePaths.userBoosts(userId))
          .limit(50)
          .get();
      final entries = <BoostHistoryEntry>[
        ...purchases.docs.map((doc) {
          final data = doc.data();
          return BoostHistoryEntry(
            id: doc.id,
            type: BoostHistoryType.purchase,
            productId: data['productId'] as String? ?? '',
            boostCount: _intOf(data['boostCount'], fallback: 1),
            createdAt: _dateOf(data['createdAt']) ?? _clock(),
            status: data['status'] as String?,
          );
        }),
        ...boosts.docs.map((doc) {
          final data = doc.data();
          return BoostHistoryEntry(
            id: doc.id,
            type: BoostHistoryType.activation,
            productId: data['productId'] as String? ?? '',
            boostCount: 1,
            createdAt: _dateOf(data['createdAt']) ?? _clock(),
            status: data['status'] as String?,
            expiresAt: _dateOf(data['expiresAt']),
          );
        }),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } on FirebaseException catch (error, stackTrace) {
      _logger?.warning(
        'Boost history read failed',
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

  @override
  Future<List<BoostPack>> loadCatalog() async {
    try {
      final snap = await _firestore
          .collection(FirestorePaths.boostProducts)
          .get();
      if (snap.docs.isEmpty) {
        return List<BoostPack>.from(BoostPackCatalog.storefrontPacks);
      }
      final parsed = BoostPackCatalog.parse(
        snap.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data.putIfAbsent('productId', () => doc.id);
          data.putIfAbsent('sku', () => doc.id);
          return data;
        }).toList(),
      );
      return parsed
          .where((pack) => pack.productId != BoostPackCatalog.legacyProductId)
          .toList();
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Boost catalog read failed; using offline packs',
        error: error,
        stackTrace: stackTrace,
      );
      return List<BoostPack>.from(BoostPackCatalog.storefrontPacks);
    }
  }

  Map<String, dynamic>? _mapOf(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(raw);
  }

  Boost? _boostFromMap(Object? raw) {
    final data = _mapOf(raw);
    if (data == null) {
      return null;
    }
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

  int _intOf(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
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
    if (reason == 'insufficient-balance') {
      return const PurchaseException(
        AppStrings.boostInsufficientBalance,
        kind: PurchaseErrorKind.insufficientBalance,
      );
    }
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
