import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_messages.dart';

void main() {
  test('unexpected failures never surface raw SDK text', () {
    const failure = UnexpectedFailure('firebase_auth/internal-error xyz');

    expect(FailureMessages.of(failure), 'Something went wrong');
    expect(FailureMessages.of(failure).toLowerCase(), isNot(contains('firebase')));
  });

  test('auth failures use the already-sanitized mapper message', () {
    const failure = AuthFailure('Invalid email or password');

    expect(FailureMessages.of(failure), 'Invalid email or password');
  });
}
