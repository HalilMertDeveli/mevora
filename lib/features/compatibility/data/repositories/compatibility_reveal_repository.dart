import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reveal.dart';

abstract class CompatibilityRevealRepository {
  Future<Result<CompatibilityReveal>> getReveal(String matchId);
}

class FunctionsCompatibilityRevealRepository
    implements CompatibilityRevealRepository {
  FunctionsCompatibilityRevealRepository({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  @override
  Future<Result<CompatibilityReveal>> getReveal(String matchId) async {
    try {
      final data = await _backend.invoke('getMatchCompatibilityReveal', {
        'matchId': matchId,
      });
      return Success(CompatibilityReveal.fromMap(data));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}

class MemoryCompatibilityRevealRepository
    implements CompatibilityRevealRepository {
  MemoryCompatibilityRevealRepository({CompatibilityReveal? seed})
    : _seed = seed ?? CompatibilityReveal.unavailable;

  final CompatibilityReveal _seed;

  @override
  Future<Result<CompatibilityReveal>> getReveal(String matchId) async {
    return Success(_seed);
  }
}
