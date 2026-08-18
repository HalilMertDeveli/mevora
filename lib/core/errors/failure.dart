import 'package:mevora/core/errors/app_exception.dart';

export 'package:mevora/core/errors/app_exception.dart'
    show AuthErrorKind, LocationErrorKind, PurchaseErrorKind;

sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

final class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}

final class AuthFailure extends Failure {
  const AuthFailure(
    super.message, {
    this.isCancelled = false,
    this.kind = AuthErrorKind.unknown,
  });

  final bool isCancelled;
  final AuthErrorKind kind;
}

final class AuthzFailure extends Failure {
  const AuthzFailure(super.message);
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

final class LocationFailure extends Failure {
  const LocationFailure(super.message, {required this.kind});

  final LocationErrorKind kind;
}

final class PurchaseFailure extends Failure {
  const PurchaseFailure(super.message, {required this.kind});

  final PurchaseErrorKind kind;
}
