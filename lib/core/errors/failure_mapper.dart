import 'package:cloud_functions/cloud_functions.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';

/// Maps infrastructure exceptions to domain failures.
abstract final class FailureMapper {
  static Failure from(Object error) {
    if (error is FirebaseFunctionsException) {
      final code = error.code.toLowerCase();
      if (code == 'unauthenticated') {
        return const AuthFailure(
          'Sign in required.',
          kind: AuthErrorKind.sessionExpired,
        );
      }
      if (code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'resource-exhausted') {
        return const NetworkFailure(AppStrings.networkError);
      }
      if (code == 'permission-denied') {
        return const PermissionFailure('Bu işlem için yetkin yok.');
      }
      if (code == 'invalid-argument' || code == 'failed-precondition') {
        // Prefer stable product copy over raw backend codes like INTERNAL.
        final message = (error.message ?? '').trim();
        if (message.isNotEmpty &&
            !message.toUpperCase().contains('INTERNAL') &&
            message.toLowerCase() != 'internal') {
          return ValidationFailure(message);
        }
      }
      // Never show opaque INTERNAL / SDK dumps to users.
      return const UnexpectedFailure(AppStrings.somethingWentWrong);
    }
    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }
    if (error is CacheException) {
      return CacheFailure(error.message);
    }
    if (error is ValidationException) {
      return ValidationFailure(error.message);
    }
    if (error is AuthException) {
      return AuthFailure(
        error.message,
        kind: error.kind,
        code: error.code,
        isCancelled:
            error.isCancelled || error.kind == AuthErrorKind.cancelled,
      );
    }
    if (error is AuthzException) {
      return AuthzFailure(error.message);
    }
    if (error is PermissionException) {
      return PermissionFailure(error.message);
    }
    if (error is NotFoundException) {
      return NotFoundFailure(error.message);
    }
    if (error is LocationException) {
      return LocationFailure(error.message, kind: error.kind);
    }
    if (error is PurchaseException) {
      return PurchaseFailure(error.message, kind: error.kind);
    }
    if (error is AppException) {
      return UnexpectedFailure(error.message);
    }
    return const UnexpectedFailure('An unexpected error occurred.');
  }
}
