import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class GetBoostProducts {
  const GetBoostProducts(this._repository);

  final PurchaseRepository _repository;

  Future<Result<List<BoostProduct>>> call() => _repository.getBoostProducts();
}
