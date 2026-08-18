import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class FakeUidSource implements AuthUidSource {
  FakeUidSource(this.currentUid);

  @override
  String? currentUid;

  @override
  Stream<String?> watchUid() => Stream.value(currentUid);
}

class FakePurchaseRepository implements PurchaseRepository {
  FakePurchaseRepository({
    this.product = const BoostProduct(
      productId: 'com.mevora.app.boost',
      title: 'Mevora Boost',
      description: 'Extra discovery visibility',
      localizedPrice: '₺29,99',
      currency: 'TRY',
      available: true,
      duration: Duration(minutes: 30),
    ),
    this.transaction = const StoreTransaction(
      platform: PurchasePlatform.android,
      productId: 'com.mevora.app.boost',
      transactionId: 'GPA.1234',
      purchaseToken: 'token',
    ),
    this.activeBoost,
    this.productFailure,
  });

  BoostProduct? product;
  StoreTransaction? transaction;
  Boost? activeBoost;
  PurchaseFailure? productFailure;
  PurchaseFailure? purchaseFailure;
  PurchaseFailure? verifyFailure;
  bool purchaseCalled = false;
  bool verifyCalled = false;
  int activeReads = 0;
  StoreTransaction? lastCompleted;

  @override
  Future<Result<BoostProduct>> getBoostProduct() async {
    final failure = productFailure;
    if (failure != null) {
      return Err(failure);
    }
    final value = product;
    if (value == null) {
      return const Err(
        PurchaseFailure(
          'Mağaza şu anda bu cihazda kullanılamıyor.',
          kind: PurchaseErrorKind.unavailable,
        ),
      );
    }
    return Success(value);
  }

  @override
  Future<Result<StoreTransaction>> purchaseBoost(BoostProduct product) async {
    purchaseCalled = true;
    final failure = purchaseFailure;
    if (failure != null) {
      return Err(failure);
    }
    return Success(transaction!);
  }

  @override
  Future<Result<Boost>> verifyBoostPurchase({
    required String userId,
    required StoreTransaction transaction,
  }) async {
    verifyCalled = true;
    final failure = verifyFailure;
    if (failure != null) {
      return Err(failure);
    }
    final now = DateTime.utc(2026, 8, 18, 12);
    final boost = Boost(
      boostId: 'b1',
      userId: userId,
      productId: transaction.productId,
      purchaseId: 'android_${transaction.transactionId}',
      status: BoostStatus.active,
      createdAt: now,
      startedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
    );
    activeBoost = boost;
    return Success(boost);
  }

  @override
  Future<Result<Boost?>> getActiveBoost(String userId) async {
    activeReads += 1;
    return Success(activeBoost);
  }

  @override
  Future<Result<void>> completeStoreTransaction(
    StoreTransaction transaction,
  ) async {
    lastCompleted = transaction;
    return const Success(null);
  }

  @override
  Future<Result<Boost?>> restorePurchases(String userId) {
    return getActiveBoost(userId);
  }
}
