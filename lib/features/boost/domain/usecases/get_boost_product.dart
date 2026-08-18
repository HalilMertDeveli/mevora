import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class GetBoostProduct {
  const GetBoostProduct(this._repository);

  final PurchaseRepository _repository;

  Future<Result<BoostProduct>> call() => _repository.getBoostProduct();
}
