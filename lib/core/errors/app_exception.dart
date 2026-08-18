sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause});
}

final class CacheException extends AppException {
  const CacheException(super.message, {super.cause});
}

final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

final class UnexpectedException extends AppException {
  const UnexpectedException(super.message, {super.cause});
}

enum AuthErrorKind {
  cancelled,
  invalidPhone,
  smsFailed,
  invalidOtp,
  expiredOtp,
  tooManyAttempts,
  smsQuota,
  firebaseUnavailable,
  network,
  disabled,
  banned,
  oauth,
  unknown,
  accountExists,
  linkingBlocked,
  notConfigured,
  invalidEmail,
  weakPassword,
  userNotFound,
  wrongPassword,
}

final class AuthException extends AppException {
  const AuthException(
    super.message, {
    super.cause,
    this.code,
    this.isCancelled = false,
    this.kind = AuthErrorKind.unknown,
  });

  final String? code;
  final bool isCancelled;
  final AuthErrorKind kind;
}

final class AuthzException extends AppException {
  const AuthzException(super.message, {super.cause, this.code});

  final String? code;
}

final class PermissionException extends AppException {
  const PermissionException(super.message, {super.cause});
}

final class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.cause});
}

enum LocationErrorKind {
  gpsDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
  timeout,
  network,
  invalidCoordinates,
  error,
}

final class LocationException extends AppException {
  const LocationException(
    super.message, {
    super.cause,
    required this.kind,
  });

  final LocationErrorKind kind;
}

enum PurchaseErrorKind {
  cancelled,
  failed,
  unavailable,
  storeDown,
  network,
  verificationFailed,
  alreadyProcessed,
  alreadyActive,
}

final class PurchaseException extends AppException {
  const PurchaseException(
    super.message, {
    super.cause,
    required this.kind,
  });

  final PurchaseErrorKind kind;
}
