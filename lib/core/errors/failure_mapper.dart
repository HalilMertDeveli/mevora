import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';

/// Maps infrastructure exceptions to domain failures.
abstract final class FailureMapper {
  static Failure from(Object error) {
    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }
    if (error is CacheException) {
      return CacheFailure(error.message);
    }
    if (error is ValidationException) {
      return ValidationFailure(error.message);
    }
    if (error is AppException) {
      return UnexpectedFailure(error.message);
    }
    return const UnexpectedFailure('An unexpected error occurred.');
  }
}
