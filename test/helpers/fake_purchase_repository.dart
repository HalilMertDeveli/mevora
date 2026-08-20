import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_credit_result.dart';
import 'package:mevora/features/boost/domain/entities/boost_history_entry.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/boost_wallet.dart';
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
      productId: BoostPackCatalog.pack1,
      title: 'Mevora Boost',
      description: 'Extra discovery visibility',
      localizedPrice: '₺49,99',
      currency: 'TRY',
      available: true,
      duration: Duration(minutes: 30),
      boostCount: 1,
      fallbackPrice: '₺49,99',
    ),
    this.transaction = const StoreTransaction(
      platform: PurchasePlatform.android,
      productId: BoostPackCatalog.pack1,
      transactionId: 'GPA.1234',
      purchaseToken: 'token',
    ),
    this.activeBoost,
    this.productFailure,
    BoostWallet? wallet,
    this.products,
    List<BoostHistoryEntry>? history,
  }) : wallet = wallet ?? const BoostWallet(),
       history = history ?? const [];

  BoostProduct? product;
  List<BoostProduct>? products;
  StoreTransaction? transaction;
  Boost? activeBoost;
  BoostWallet wallet;
  List<BoostHistoryEntry> history;
  PurchaseFailure? productFailure;
  PurchaseFailure? purchaseFailure;
  PurchaseFailure? verifyFailure;
  PurchaseFailure? activateFailure;
  bool purchaseCalled = false;
  bool verifyCalled = false;
  bool activateCalled = false;
  int activeReads = 0;
  StoreTransaction? lastCompleted;

  List<BoostProduct> get _packs =>
      products ??
      [
        ?product,
        const BoostProduct(
          productId: BoostPackCatalog.pack5,
          title: '5 Boost',
          description: 'Extra discovery visibility',
          localizedPrice: '₺199,99',
          currency: 'TRY',
          available: true,
          duration: Duration(minutes: 30),
          displayOrder: 1,
          boostCount: 5,
          fallbackPrice: '₺199,99',
        ),
        const BoostProduct(
          productId: BoostPackCatalog.pack10,
          title: '10 Boost',
          description: 'Extra discovery visibility',
          localizedPrice: '₺349,99',
          currency: 'TRY',
          available: true,
          duration: Duration(minutes: 30),
          displayOrder: 2,
          boostCount: 10,
          fallbackPrice: '₺349,99',
        ),
      ];

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
  Future<Result<List<BoostProduct>>> getBoostProducts() async {
    final failure = productFailure;
    if (failure != null) {
      return Err(failure);
    }
    return Success(_packs);
  }

  @override
  Future<Result<StoreTransaction>> purchaseBoost(BoostProduct product) async {
    purchaseCalled = true;
    final failure = purchaseFailure;
    if (failure != null) {
      return Err(failure);
    }
    return Success(
      StoreTransaction(
        platform: transaction?.platform ?? PurchasePlatform.android,
        productId: product.productId,
        transactionId: transaction?.transactionId ?? 'GPA.1234',
        purchaseToken: transaction?.purchaseToken,
      ),
    );
  }

  @override
  Future<Result<BoostCreditResult>> verifyBoostPurchase({
    required String userId,
    required StoreTransaction transaction,
  }) async {
    verifyCalled = true;
    final failure = verifyFailure;
    if (failure != null) {
      return Err(failure);
    }
    final added = BoostPackCatalog.boostCountFor(transaction.productId);
    final count = added < 1 ? 1 : added;
    wallet = BoostWallet(balance: wallet.balance + count);
    history = [
      BoostHistoryEntry(
        id: 'p-${transaction.transactionId}',
        type: BoostHistoryType.purchase,
        productId: transaction.productId,
        boostCount: count,
        createdAt: DateTime.utc(2026, 8, 18, 12),
        status: 'verified',
      ),
      ...history,
    ];
    return Success(
      BoostCreditResult(
        purchaseId: 'android_${transaction.transactionId}',
        productId: transaction.productId,
        boostCount: count,
        balance: wallet.balance,
      ),
    );
  }

  @override
  Future<Result<Boost>> activateBoost(String userId) async {
    activateCalled = true;
    final failure = activateFailure;
    if (failure != null) {
      return Err(failure);
    }
    if (wallet.balance < 1) {
      return const Err(
        PurchaseFailure(
          'Aktif etmek için Boost bakiyen yok.',
          kind: PurchaseErrorKind.insufficientBalance,
        ),
      );
    }
    final now = DateTime.utc(2026, 8, 18, 12);
    wallet = BoostWallet(balance: wallet.balance - 1);
    final boost = Boost(
      boostId: 'b1',
      userId: userId,
      productId: 'activate',
      purchaseId: '',
      status: BoostStatus.active,
      createdAt: now,
      startedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
    );
    activeBoost = boost;
    history = [
      BoostHistoryEntry(
        id: 'b1',
        type: BoostHistoryType.activation,
        productId: 'activate',
        createdAt: now,
        status: 'active',
        expiresAt: boost.expiresAt,
      ),
      ...history,
    ];
    return Success(boost);
  }

  @override
  Future<Result<Boost?>> getActiveBoost(String userId) async {
    activeReads += 1;
    return Success(activeBoost);
  }

  @override
  Future<Result<BoostWallet>> getWallet(String userId) async {
    return Success(wallet);
  }

  @override
  Future<Result<List<BoostHistoryEntry>>> getHistory(String userId) async {
    return Success(history);
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
