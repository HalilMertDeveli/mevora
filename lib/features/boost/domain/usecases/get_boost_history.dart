import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost_history_entry.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class GetBoostHistory {
  const GetBoostHistory(this._repository);

  final PurchaseRepository _repository;

  Future<Result<List<BoostHistoryEntry>>> call(String userId) {
    return _repository.getHistory(userId);
  }
}
