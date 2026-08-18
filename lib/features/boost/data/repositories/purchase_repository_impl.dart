import 'dart:async';

import 'package:mevora/core/cache/memory_cache.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/boost/data/datasources/firebase_purchase_data_source.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';
import 'package:mevora/features/boost/domain/services/purchase_verification_service.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  PurchaseRepositoryImpl({
    required StorePurchaseDataSource store,
    required PurchaseRemoteDataSource remote,
    required AuthUidSource uidSource,
    BoostProductConfig config = const BoostProductConfig(),
    PurchaseVerificationService? verification,
    DateTime Function()? clock,
  }) : _store = store,
       _remote = remote,
       _uidSource = uidSource,
       _config = config,
       _verification =
           verification ?? PurchaseVerificationService(config: config),
       _cache = MemoryCache<String, _CachedBoost>(
         ttl: const Duration(minutes: 2),
       ),
       _clock = clock ?? DateTime.now;

  final StorePurchaseDataSource _store;
  final PurchaseRemoteDataSource _remote;
  final AuthUidSource _uidSource;
  final BoostProductConfig _config;
  final PurchaseVerificationService _verification;
  final MemoryCache<String, _CachedBoost> _cache;
  final DateTime Function() _clock;

  @override
  Future<Result<BoostProduct>> getBoostProduct() async {
    try {
      final product = await _store.loadProduct(_config);
      return Success(product);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<StoreTransaction>> purchaseBoost(BoostProduct product) async {
    try {
      final pending = _store.purchaseEvents
          .where(
            (event) =>
                event.status == StorePurchaseStatus.purchased ||
                event.status == StorePurchaseStatus.restored ||
                event.status == StorePurchaseStatus.cancelled ||
                event.status == StorePurchaseStatus.error,
          )
          .first;
      await _store.buy(product);
      final event = await pending.timeout(const Duration(minutes: 5));
      if (event.status == StorePurchaseStatus.cancelled) {
        return const Err(
          PurchaseFailure(
            AppStrings.boostPurchaseCancelled,
            kind: PurchaseErrorKind.cancelled,
          ),
        );
      }
      if (event.status == StorePurchaseStatus.error ||
          event.transaction == null) {
        return Err(
          PurchaseFailure(
            AppStrings.boostPurchaseFailed,
            kind: event.kind ?? PurchaseErrorKind.failed,
          ),
        );
      }
      return Success(event.transaction!);
    } on TimeoutException {
      return const Err(
        PurchaseFailure(
          AppStrings.boostStoreDown,
          kind: PurchaseErrorKind.storeDown,
        ),
      );
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<Boost>> verifyBoostPurchase({
    required String userId,
    required StoreTransaction transaction,
  }) async {
    try {
      final expectedUid = _uidSource.currentUid;
      if (expectedUid == null || expectedUid != userId) {
        return const Err(
          PurchaseFailure(
            AppStrings.boostVerificationFailed,
            kind: PurchaseErrorKind.verificationFailed,
          ),
        );
      }
      final decision = _verification.decide(
        uid: userId,
        productId: transaction.productId,
        transactionId: transaction.transactionId,
        platform: transaction.platform,
      );
      if (decision.outcome == VerificationOutcome.invalidProduct ||
          decision.outcome == VerificationOutcome.invalidTransaction ||
          decision.outcome == VerificationOutcome.invalidUid) {
        return const Err(
          PurchaseFailure(
            AppStrings.boostVerificationFailed,
            kind: PurchaseErrorKind.verificationFailed,
          ),
        );
      }
      final boost = await _remote.verifyPurchase(
        userId: userId,
        transaction: transaction,
      );
      _cache.set(_cacheKeyFor(userId), _CachedBoost(boost));
      return Success(boost);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<Boost?>> getActiveBoost(String userId) async {
    final cached = _cache.get(_cacheKeyFor(userId));
    if (cached != null) {
      final boost = cached.boost;
      if (boost != null && !boost.isActiveAt(_clock())) {
        return const Success(null);
      }
      return Success(boost);
    }
    try {
      final boost = await _remote.loadActiveBoost(userId);
      final active = boost != null && boost.isActiveAt(_clock()) ? boost : null;
      _cache.set(_cacheKeyFor(userId), _CachedBoost(active));
      return Success(active);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<void>> completeStoreTransaction(
    StoreTransaction transaction,
  ) async {
    try {
      await _store.complete(transaction);
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<Boost?>> restorePurchases(String userId) async {
    try {
      await _store.restore();
      _cache.invalidate(_cacheKeyFor(userId));
      return getActiveBoost(userId);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  String _cacheKeyFor(String userId) => 'active:$userId';
}

class _CachedBoost {
  const _CachedBoost(this.boost);

  final Boost? boost;
}
