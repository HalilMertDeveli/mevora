import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';

void main() {
  test('maps known exceptions to matching failures', () {
    expect(
      FailureMapper.from(const NetworkException('offline')),
      isA<NetworkFailure>(),
    );
    expect(
      FailureMapper.from(const ValidationException('invalid')),
      isA<ValidationFailure>(),
    );
    expect(
      FailureMapper.from(
        const AuthException('nope', kind: AuthErrorKind.wrongPassword),
      ),
      isA<AuthFailure>(),
    );
  });

  test('maps unknown errors to UnexpectedFailure', () {
    expect(FailureMapper.from(StateError('boom')), isA<UnexpectedFailure>());
  });

  test('Result exposes success values', () {
    const result = Success<int>(7);

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, 7);
  });

  test('Result hides error values', () {
    const result = Err<int>(UnexpectedFailure('failed'));

    expect(result.isSuccess, isFalse);
    expect(result.valueOrNull, isNull);
  });
}
