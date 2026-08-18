import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class PurchaseBoost {
  const PurchaseBoost(this._repository);

  final PurchaseRepository _repository;

  Future<Result<StoreTransaction>> call(BoostProduct product) {
    return _repository.purchaseBoost(product);
  }
}
