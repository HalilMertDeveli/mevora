import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';

class _FakeFirebaseAuthException implements Exception {
  _FakeFirebaseAuthException({required this.code, this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'FirebaseAuthException($code, $message)';
}

void main() {
  test('maps email auth codes to user-facing exceptions', () {
    expect(
      AuthErrorMapper.fromCode('email-already-in-use').kind,
      AuthErrorKind.emailInUse,
    );
    expect(
      AuthErrorMapper.fromCode('wrong-password').message,
      AuthMessages.wrongPassword,
    );
    expect(
      AuthErrorMapper.fromCode('user-not-found').kind,
      AuthErrorKind.userNotFound,
    );
    expect(
      AuthErrorMapper.fromCode('weak-password').kind,
      AuthErrorKind.weakPassword,
    );
  });

  test('maps cancelled codes', () {
    final exception = AuthErrorMapper.fromCode('canceled');
    expect(exception.kind, AuthErrorKind.cancelled);
    expect(exception.message, AuthMessages.cancelled);
  });

  test('never exposes raw firebase codes', () {
    final exception = AuthErrorMapper.fromCode('totally-unknown-code');
    expect(exception.message.contains('firebase'), isFalse);
    expect(exception.message, AuthMessages.unknown);
  });

  test('maps phone-auth send failures without exposing Firebase codes', () {
    expect(
      AuthErrorMapper.fromCode('operation-not-allowed').kind,
      AuthErrorKind.notConfigured,
    );
    expect(
      AuthErrorMapper.fromCode('firebase_auth/invalid-app-credential').kind,
      AuthErrorKind.appVerification,
    );
    expect(
      AuthErrorMapper.fromCode('sms-region-restricted').kind,
      AuthErrorKind.smsFailed,
    );
    expect(
      AuthErrorMapper.fromCode('invalid-app-credential').message,
      AuthMessages.appVerification,
    );
    expect(
      AuthErrorMapper.fromCode('captcha-check-failed').kind,
      AuthErrorKind.appVerification,
    );
    expect(
      AuthErrorMapper.fromCode('missing-client-identifier').kind,
      AuthErrorKind.appVerification,
    );
    expect(
      AuthErrorMapper.fromCode('invalid-phone-number').kind,
      AuthErrorKind.invalidPhone,
    );
    expect(
      AuthErrorMapper.fromCode('invalid-verification-code').kind,
      AuthErrorKind.invalidOtp,
    );
    expect(
      AuthErrorMapper.fromCode('session-expired').kind,
      AuthErrorKind.sessionExpired,
    );
    expect(
      AuthErrorMapper.fromCode('session-expired').message,
      AuthMessages.sessionExpired,
    );
    expect(
      AuthErrorMapper.fromCode('too-many-requests').kind,
      AuthErrorKind.tooManyAttempts,
    );
    expect(
      AuthErrorMapper.fromCode('quota-exceeded').kind,
      AuthErrorKind.smsQuota,
    );
    expect(
      AuthErrorMapper.fromCode('network-request-failed').kind,
      AuthErrorKind.network,
    );
    expect(
      AuthErrorMapper.fromCode('user-disabled').kind,
      AuthErrorKind.disabled,
    );
  });

  test('maps BILLING_NOT_ENABLED / 17499 to clear billing message', () {
    final byCode = AuthErrorMapper.fromCode('billing-not-enabled');
    expect(byCode.kind, AuthErrorKind.billingNotEnabled);
    expect(byCode.message, AuthMessages.billingNotEnabled);
    expect(byCode.message.contains('BILLING'), isFalse);

    final prefixed = AuthErrorMapper.fromCode('firebase_auth/billing-not-enabled');
    expect(prefixed.kind, AuthErrorKind.billingNotEnabled);

    final wrapped = AuthErrorMapper.map(
      _FakeFirebaseAuthException(
        code: 'internal-error',
        message: 'An internal error has occurred. [ BILLING_NOT_ENABLED ]',
      ),
    );
    expect(wrapped.kind, AuthErrorKind.billingNotEnabled);
    expect(wrapped.message, AuthMessages.billingNotEnabled);
    expect(wrapped.message.contains('BILLING_NOT_ENABLED'), isFalse);
    expect(wrapped.message.contains('internal'), isFalse);

    final byStatus = AuthErrorMapper.map(
      _FakeFirebaseAuthException(
        code: 'unknown',
        message:
            'SMS verification code request failed: unknown status code: 17499',
      ),
    );
    expect(byStatus.kind, AuthErrorKind.billingNotEnabled);
    expect(byStatus.message, AuthMessages.billingNotEnabled);
  });
}
