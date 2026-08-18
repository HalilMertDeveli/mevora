import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class GetActiveBoost {
  const GetActiveBoost(this._repository);

  final PurchaseRepository _repository;

  Future<Result<Boost?>> call(String userId) {
    return _repository.getActiveBoost(userId);
  }
}
