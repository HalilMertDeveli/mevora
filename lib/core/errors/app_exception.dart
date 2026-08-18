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
