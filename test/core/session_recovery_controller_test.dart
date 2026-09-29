import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/session/session_recovery_controller.dart';

void main() {
  test(
    'SessionRecoveryController recovers without Firebase singletons',
    () async {
      final controller = SessionRecoveryController.detached();
      await controller.recover(reason: 'test');
      controller.dispose();
    },
  );

  group('isSessionRevoked', () {
    bool revoked(String code, [String? message]) =>
        SessionRecoveryController.isSessionRevoked(
          FirebaseAuthException(code: code, message: message),
        );

    test('a refresh token the backend no longer knows is revoked', () {
      // Exactly what Android reported after the Auth emulator lost the user:
      // code "unknown", backend code only in the message.
      expect(
        revoked(
          'unknown',
          'An internal error has occurred. [ INVALID_REFRESH_TOKEN ]',
        ),
        isTrue,
      );
    });

    test('deleted, disabled and expired accounts are revoked', () {
      expect(revoked('user-not-found'), isTrue);
      expect(revoked('user-disabled'), isTrue);
      expect(revoked('user-token-expired'), isTrue);
      expect(revoked('invalid-user-token'), isTrue);
    });

    test('transient failures keep the session', () {
      expect(revoked('network-request-failed'), isFalse);
      expect(revoked('too-many-requests'), isFalse);
      expect(
        revoked('internal-error', 'An internal error has occurred.'),
        isFalse,
      );
      expect(revoked('unknown'), isFalse);
    });

    test('errors that are not auth errors keep the session', () {
      expect(
        SessionRecoveryController.isSessionRevoked(
          Exception('INVALID_REFRESH_TOKEN'),
        ),
        isFalse,
      );
    });
  });
}
