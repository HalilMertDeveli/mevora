import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';

/// Maps infrastructure error codes to Turkish [AuthException]s.
///
/// Never returns raw `firebase_auth/` strings.
abstract final class AuthErrorMapper {
  static AuthException map(Object error, {StackTrace? stackTrace}) {
    if (error is AuthException) {
      return error;
    }
    final code = _codeOf(error);
    return fromCode(code, cause: error);
  }

  static AuthException fromCode(String? code, {Object? cause}) {
    final normalized = (code ?? '').toLowerCase().replaceAll('_', '-');
    final kind = kindFor(normalized);
    return AuthException(
      _messageFor(kind),
      kind: kind,
      cause: cause,
      isCancelled: kind == AuthErrorKind.cancelled,
    );
  }

  static AuthErrorKind kindFor(String code) {
    return switch (code) {
      'canceled' ||
      'cancelled' ||
      'web-context-canceled' ||
      'web-context-cancelled' ||
      'sign-in-canceled' ||
      'sign-in-cancelled' ||
      'aborted' =>
        AuthErrorKind.cancelled,
      'invalid-phone-number' ||
      'missing-phone-number' ||
      'invalid-phone' =>
        AuthErrorKind.invalidPhone,
      'captcha-check-failed' ||
      'missing-client-identifier' ||
      'invalid-app-credential' ||
      'app-not-authorized' =>
        AuthErrorKind.smsFailed,
      'invalid-verification-code' ||
      'invalid-verification-id' ||
      'missing-verification-code' ||
      'missing-verification-id' =>
        AuthErrorKind.invalidOtp,
      'session-expired' || 'code-expired' => AuthErrorKind.expiredOtp,
      'quota-exceeded' => AuthErrorKind.smsQuota,
      'too-many-requests' ||
      'resource-exhausted' =>
        AuthErrorKind.tooManyAttempts,
      'unavailable' ||
      'internal' ||
      'deadline-exceeded' ||
      'data-loss' =>
        AuthErrorKind.firebaseUnavailable,
      'network-request-failed' || 'network' => AuthErrorKind.network,
      'user-disabled' || 'disabled' => AuthErrorKind.disabled,
      'user-banned' || 'banned' => AuthErrorKind.banned,
      'account-exists-with-different-credential' ||
      'credential-already-in-use' ||
      'email-already-in-use' ||
      'already-exists' ||
      'failed-precondition' ||
      'provider-already-linked' =>
        AuthErrorKind.accountExists,
      'linking-blocked' => AuthErrorKind.linkingBlocked,
      'operation-not-allowed' ||
      'user-mismatch' ||
      'no-such-provider' =>
        AuthErrorKind.oauth,
      'not-configured' => AuthErrorKind.notConfigured,
      'invalid-email' => AuthErrorKind.invalidEmail,
      'weak-password' => AuthErrorKind.weakPassword,
      'user-not-found' => AuthErrorKind.userNotFound,
      'wrong-password' ||
      'invalid-credential' ||
      'invalid-login-credentials' =>
        AuthErrorKind.wrongPassword,
      _ => AuthErrorKind.unknown,
    };
  }

  static String _messageFor(AuthErrorKind kind) {
    return switch (kind) {
      AuthErrorKind.cancelled => AuthMessages.cancelled,
      AuthErrorKind.invalidPhone => AuthMessages.invalidPhone,
      AuthErrorKind.smsFailed => AuthMessages.smsFailed,
      AuthErrorKind.invalidOtp => AuthMessages.invalidOtp,
      AuthErrorKind.expiredOtp => AuthMessages.expiredOtp,
      AuthErrorKind.tooManyAttempts => AuthMessages.tooManyAttempts,
      AuthErrorKind.smsQuota => AuthMessages.smsQuota,
      AuthErrorKind.firebaseUnavailable => AuthMessages.firebaseUnavailable,
      AuthErrorKind.network => AuthMessages.network,
      AuthErrorKind.disabled => AuthMessages.disabled,
      AuthErrorKind.banned => AuthMessages.banned,
      AuthErrorKind.oauth => AuthMessages.oauth,
      AuthErrorKind.unknown => AuthMessages.unknown,
      AuthErrorKind.accountExists => AuthMessages.accountExists,
      AuthErrorKind.linkingBlocked => AuthMessages.linkingBlocked,
      AuthErrorKind.notConfigured => AuthMessages.notConfigured,
      AuthErrorKind.invalidEmail => AuthMessages.invalidEmail,
      AuthErrorKind.weakPassword => AuthMessages.weakPassword,
      AuthErrorKind.userNotFound => AuthMessages.userNotFound,
      AuthErrorKind.wrongPassword => AuthMessages.wrongPassword,
    };
  }

  static String? _codeOf(Object error) {
    try {
      final dynamic value = error;
      final code = value.code;
      if (code is String) {
        return code;
      }
      if (code is Enum) {
        return code.name;
      }
    } on Object {
      return null;
    }
    return null;
  }
}

/// Email equality is not a safe signal to merge Google / Apple relay / phone /
/// Spotify identities. Linking is always an explicit user action.
abstract final class AccountLinkingPolicy {
  static bool shouldAutoMergeByEmail({
    required String? existingEmail,
    required String? incomingEmail,
  }) {
    return false;
  }
}
