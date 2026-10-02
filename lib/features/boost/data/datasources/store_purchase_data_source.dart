import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

enum StorePurchaseStatus { pending, purchased, restored, cancelled, error }

class StorePurchaseEvent {
  const StorePurchaseEvent({
    required this.status,
    this.transaction,
    this.kind,
  });

  final StorePurchaseStatus status;
  final StoreTransaction? transaction;
  final PurchaseErrorKind? kind;
}

/// StoreKit / Play Billing access. UI never depends on this type.
abstract class StorePurchaseDataSource {
  Future<bool> isStoreAvailable();

  Future<BoostProduct> loadProduct(BoostProductConfig config);

  Future<List<BoostProduct>> loadProducts(BoostProductConfig config);

  Stream<StorePurchaseEvent> get purchaseEvents;

  Future<void> buy(BoostProduct product);

  Future<void> complete(StoreTransaction transaction);

  Future<void> restore();

  /// Purchases the store still holds: paid for, and not completed yet.
  ///
  /// Asked of the store directly. Nothing is emitted on [purchaseEvents], which
  /// every product the app sells listens to, and nothing is asked of a store
  /// that hands unfinished purchases back by itself — the list is empty there.
  Future<List<StoreTransaction>> outstandingPurchases();
}
