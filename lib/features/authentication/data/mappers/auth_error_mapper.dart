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
    if (_looksLikeBillingNotEnabled(error)) {
      return AuthException(
        AuthMessages.billingNotEnabled,
        kind: AuthErrorKind.billingNotEnabled,
        cause: error,
      );
    }
    final code = _codeOf(error);
    return fromCode(code, cause: error);
  }

  static AuthException fromCode(String? code, {Object? cause}) {
    if (_looksLikeBillingNotEnabled(cause) ||
        _haystackContainsBilling(code)) {
      return AuthException(
        AuthMessages.billingNotEnabled,
        kind: AuthErrorKind.billingNotEnabled,
        cause: cause,
      );
    }
    var normalized = (code ?? '').toLowerCase().replaceAll('_', '-');
    for (final prefix in const ['firebase-auth/', 'auth/']) {
      if (normalized.startsWith(prefix)) {
        normalized = normalized.substring(prefix.length);
      }
    }
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
      'app-not-authorized' ||
      'sms-region-restricted' ||
      'sms-region-restriction' =>
        AuthErrorKind.smsFailed,
      'invalid-verification-code' ||
      'invalid-verification-id' ||
      'missing-verification-code' ||
      'missing-verification-id' =>
        AuthErrorKind.invalidOtp,
      'code-expired' => AuthErrorKind.expiredOtp,
      'session-expired' => AuthErrorKind.sessionExpired,
      'quota-exceeded' => AuthErrorKind.smsQuota,
      'too-many-requests' ||
      'resource-exhausted' =>
        AuthErrorKind.tooManyAttempts,
      'unavailable' ||
      'internal' ||
      'internal-error' ||
      'deadline-exceeded' ||
      'data-loss' =>
        AuthErrorKind.firebaseUnavailable,
      'network-request-failed' || 'network' => AuthErrorKind.network,
      'user-disabled' || 'disabled' => AuthErrorKind.disabled,
      'user-banned' || 'banned' => AuthErrorKind.banned,
      'account-exists-with-different-credential' ||
      'credential-already-in-use' ||
      'already-exists' ||
      'failed-precondition' ||
      'provider-already-linked' =>
        AuthErrorKind.accountExists,
      'email-already-in-use' => AuthErrorKind.emailInUse,
      'linking-blocked' => AuthErrorKind.linkingBlocked,
      'user-mismatch' || 'no-such-provider' => AuthErrorKind.oauth,
      'billing-not-enabled' => AuthErrorKind.billingNotEnabled,
      'operation-not-allowed' ||
      'not-configured' ||
      'providerconfigurationerror' ||
      'provider-configuration-error' =>
        AuthErrorKind.notConfigured,
      'clientconfigurationerror' ||
      'client-configuration-error' =>
        AuthErrorKind.oauth,
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
      AuthErrorKind.sessionExpired => AuthMessages.sessionExpired,
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
      AuthErrorKind.billingNotEnabled => AuthMessages.billingNotEnabled,
      AuthErrorKind.invalidEmail => AuthMessages.invalidEmail,
      AuthErrorKind.weakPassword => AuthMessages.weakPassword,
      AuthErrorKind.userNotFound => AuthMessages.userNotFound,
      AuthErrorKind.wrongPassword => AuthMessages.wrongPassword,
      AuthErrorKind.emailInUse => AuthMessages.emailInUse,
    };
  }

  /// Firebase often wraps Phone Auth billing failures as `internal` /
  /// `internal-error` with `BILLING_NOT_ENABLED` (status 17499) in the message.
  static bool _looksLikeBillingNotEnabled(Object? error) {
    if (error == null) {
      return false;
    }
    final code = _codeOf(error);
    final message = _messageOf(error);
    return _haystackContainsBilling(code) || _haystackContainsBilling(message);
  }

  static bool _haystackContainsBilling(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    final haystack = value.toLowerCase().replaceAll('_', '-');
    return haystack.contains('billing-not-enabled') ||
        haystack.contains('17499');
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

  static String? _messageOf(Object error) {
    try {
      final dynamic value = error;
      final message = value.message;
      if (message is String) {
        return message;
      }
    } on Object {
      // Fall through to toString for plain Error / Exception.
    }
    final text = error.toString();
    return text.isEmpty ? null : text;
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
