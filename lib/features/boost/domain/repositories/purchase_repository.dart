import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

/// Purchase surface. Presentation never talks to StoreKit, Play, or Firebase.
abstract class PurchaseRepository {
  Future<Result<BoostProduct>> getBoostProduct();

  Future<Result<StoreTransaction>> purchaseBoost(BoostProduct product);

  Future<Result<Boost>> verifyBoostPurchase({
    required String userId,
    required StoreTransaction transaction,
  });

  Future<Result<Boost?>> getActiveBoost(String userId);

  /// Finish / consume the store transaction after backend confirmation.
  Future<Result<void>> completeStoreTransaction(StoreTransaction transaction);

  /// Consumable restore: iOS does not restore consumables; Android may
  /// redeliver unconsumed purchases. History is keyed by Firebase UID.
  Future<Result<Boost?>> restorePurchases(String userId);
}
