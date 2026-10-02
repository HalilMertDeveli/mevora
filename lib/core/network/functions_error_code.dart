import 'package:cloud_functions/cloud_functions.dart';

/// A callable's status code in the form every caller compares it against.
///
/// On Android, cloud_functions (before 6.5.0) lower-cases the status name
/// with the phone's own locale. In Turkish and Azerbaijani an upper-case "I"
/// lower-cases to the dotless "ı", so `FAILED_PRECONDITION` arrives as
/// `faıled-precondıtıon` and `UNAUTHENTICATED` as `unauthentıcated`. No
/// `error.code == 'failed-precondition'` check matches on those phones, and
/// every specific message falls through to the generic one.
String canonicalFunctionsErrorCode(String code) => code.replaceAll('ı', 'i');

/// [error] with its code in the canonical form; the same object when the code
/// is already canonical.
FirebaseFunctionsException canonicalFunctionsError(
  FirebaseFunctionsException error,
) {
  final code = canonicalFunctionsErrorCode(error.code);
  if (code == error.code) {
    return error;
  }
  return _CanonicalFunctionsException(
    message: error.message ?? '',
    code: code,
    stackTrace: error.stackTrace,
    details: error.details,
  );
}

/// Runs [call] and reports a callable failure with a canonical code.
///
/// Every `httpsCallable(...).call` in the app goes through this, so nothing
/// downstream has to know about the phone's locale.
Future<T> withCanonicalFunctionsErrors<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on FirebaseFunctionsException catch (error, stackTrace) {
    final canonical = canonicalFunctionsError(error);
    if (identical(canonical, error)) {
      rethrow;
    }
    Error.throwWithStackTrace(canonical, stackTrace);
  }
}

class _CanonicalFunctionsException extends FirebaseFunctionsException {
  _CanonicalFunctionsException({
    required super.message,
    required super.code,
    super.stackTrace,
    super.details,
  });
}
