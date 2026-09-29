import 'dart:async';

import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

/// Stands in for Play Billing / StoreKit when the app runs against the
/// Firebase Emulator Suite.
///
/// An emulator image has no Play Store product for Mevora, so the real store
/// returns nothing, every price reads "unavailable" and nothing can be bought —
/// which makes the purchase flow impossible to exercise locally. This store
/// answers instead, with a fixed test price.
///
/// It replaces only the store. What it emits is an ordinary purchase event with
/// an opaque token, which the repository hands to `verifyBoostPurchase` exactly
/// as it would a real one; the Functions emulator is what accepts it. So a test
/// purchase still runs the callable, the credit service and the wallet write.
///
/// Wired only when `AppConfig.useEmulators` is true, which is never the case
/// outside a development build.
class EmulatorStorePurchaseDataSource implements StorePurchaseDataSource {
  EmulatorStorePurchaseDataSource({
    this.testPrice = defaultTestPrice,
    this.platform = PurchasePlatform.android,
  });

  /// What every test product costs. Visibly a test figure, not a real price.
  static const String defaultTestPrice = '₺10,00';

  /// Marks tokens this store minted. The backend emulator path keys off it.
  static const String tokenPrefix = 'emulator-test:';

  final String testPrice;
  final PurchasePlatform platform;

  final StreamController<StorePurchaseEvent> _events =
      StreamController<StorePurchaseEvent>.broadcast();
  int _sequence = 0;

  @override
  Stream<StorePurchaseEvent> get purchaseEvents => _events.stream;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<BoostProduct> loadProduct(BoostProductConfig config) async {
    return _productFor(config.productIdFor(platform), config);
  }

  @override
  Future<List<BoostProduct>> loadProducts(BoostProductConfig config) async {
    return BoostPackCatalog.storefrontSkus
        .map((sku) => _productFor(sku, config))
        .toList(growable: false);
  }

  @override
  Future<void> buy(BoostProduct product) async {
    _sequence += 1;
    final transactionId =
        'emulator-${DateTime.now().microsecondsSinceEpoch}-$_sequence';
    final transaction = StoreTransaction(
      platform: platform,
      productId: product.productId,
      transactionId: transactionId,
      purchaseToken: '$tokenPrefix${product.productId}:$transactionId',
    );
    // A real store reports after its sheet closes, never synchronously inside
    // buy(). Keeping that shape means the repository's wait-for-event path is
    // the one being exercised.
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        if (!_events.isClosed) {
          _events.add(
            StorePurchaseEvent(
              status: StorePurchaseStatus.purchased,
              transaction: transaction,
            ),
          );
        }
      }),
    );
  }

  @override
  Future<void> complete(StoreTransaction transaction) async {}

  /// Boost packs are consumables; a store has nothing to restore for them.
  @override
  Future<void> restore() async {}

  BoostProduct _productFor(String productId, BoostProductConfig config) {
    final pack = BoostPackCatalog.packFor(productId);
    return BoostProduct(
      productId: productId,
      title: pack?.title ?? productId,
      description: '',
      localizedPrice: testPrice,
      currency: 'TRY',
      available: true,
      duration: pack?.duration ?? config.duration,
      displayOrder: pack?.displayOrder ?? config.displayOrder,
      boostCount: pack?.boostCount ?? 0,
      featured: pack?.featured ?? false,
    );
  }

  Future<void> dispose() => _events.close();
}
