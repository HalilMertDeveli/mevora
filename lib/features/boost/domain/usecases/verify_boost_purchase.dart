import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost_credit_result.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class VerifyBoostPurchase {
  const VerifyBoostPurchase(this._repository);

  final PurchaseRepository _repository;

  Future<Result<BoostCreditResult>> call({
    required String userId,
    required StoreTransaction transaction,
  }) {
    return _repository.verifyBoostPurchase(
      userId: userId,
      transaction: transaction,
    );
  }
}
