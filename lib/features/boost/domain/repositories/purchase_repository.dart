import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_credit_result.dart';
import 'package:mevora/features/boost/domain/entities/boost_history_entry.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/boost_wallet.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

/// Purchase surface. Presentation never talks to StoreKit, Play, or Firebase.
abstract class PurchaseRepository {
  Future<Result<BoostProduct>> getBoostProduct();

  Future<Result<List<BoostProduct>>> getBoostProducts();

  Future<Result<StoreTransaction>> purchaseBoost(BoostProduct product);

  Future<Result<BoostCreditResult>> verifyBoostPurchase({
    required String userId,
    required StoreTransaction transaction,
  });

  Future<Result<Boost>> activateBoost(String userId);

  Future<Result<Boost?>> getActiveBoost(String userId);

  Future<Result<BoostWallet>> getWallet(String userId);

  Future<Result<List<BoostHistoryEntry>>> getHistory(String userId);

  /// Finish / consume the store transaction after backend confirmation.
  Future<Result<void>> completeStoreTransaction(StoreTransaction transaction);

  /// Consumable restore: iOS does not restore consumables; Android may
  /// redeliver unconsumed purchases. History is keyed by Firebase UID.
  Future<Result<Boost?>> restorePurchases(String userId);
}
