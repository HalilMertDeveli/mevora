import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost_wallet.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class GetBoostWallet {
  const GetBoostWallet(this._repository);

  final PurchaseRepository _repository;

  Future<Result<BoostWallet>> call(String userId) {
    return _repository.getWallet(userId);
  }
}
