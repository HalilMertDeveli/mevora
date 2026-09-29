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
      AuthErrorKind.expiredOtp,
    );
    expect(
      AuthErrorMapper.fromCode('session-expired').message,
      AuthMessages.expiredOtp,
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
    expect(byStatus.code, 'billing-not-enabled');
  });

  test('keeps the diagnostic code on billing and app-verification paths', () {
    // The debug `Firebase: <code>` line is only drawn when a code survives.
    expect(
      AuthErrorMapper.fromCode('BILLING_NOT_ENABLED').code,
      'billing-not-enabled',
    );
    expect(
      AuthErrorMapper.fromCode('firebase_auth/invalid-app-credential').code,
      'invalid-app-credential',
    );
    expect(
      AuthErrorMapper.fromCode('missing-client-identifier').code,
      'missing-client-identifier',
    );
  });

  test('maps the SMS region policy rejection to sms-region-restricted', () {
    // Exact backend wording for a number whose region is not allowlisted.
    final regionBlocked = AuthErrorMapper.map(
      _FakeFirebaseAuthException(
        code: 'operation-not-allowed',
        message:
            'OPERATION_NOT_ALLOWED : SMS unable to be sent until this region '
            'enabled by the app developer.',
      ),
    );
    expect(regionBlocked.kind, AuthErrorKind.smsFailed);
    expect(regionBlocked.code, 'sms-region-restricted');

    // A provider that is genuinely disabled still reads as not configured.
    final providerDisabled = AuthErrorMapper.map(
      _FakeFirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'This operation is not allowed.',
      ),
    );
    expect(providerDisabled.kind, AuthErrorKind.notConfigured);
    expect(providerDisabled.code, 'operation-not-allowed');
  });
}
