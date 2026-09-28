import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';

/// A callable that always fails with the given Cloud Functions error code.
class _FailingBackend implements BackendCallable {
  _FailingBackend(this.code);

  final String code;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? payload,
  ]) async {
    throw FirebaseFunctionsException(code: code, message: 'from-$name');
  }
}

HumorRepositoryImpl _repository(String code) => HumorRepositoryImpl(
  dataSource: FunctionsHumorDataSource(backend: _FailingBackend(code)),
);

void main() {
  test('callable error codes keep their meaning', () async {
    final cases = <String, Type>{
      'unavailable': NetworkFailure,
      'deadline-exceeded': NetworkFailure,
      'unauthenticated': AuthFailure,
      'permission-denied': AuthzFailure,
      'not-found': NotFoundFailure,
      'failed-precondition': UnexpectedFailure,
      'internal': UnexpectedFailure,
    };
    for (final entry in cases.entries) {
      final result = await _repository(entry.key).getFeed();
      expect(
        result.failureOrNull.runtimeType,
        entry.value,
        reason: 'code ${entry.key}',
      );
    }
  });

  test('the code survives into the failure for diagnostics', () async {
    final result = await _repository(
      'failed-precondition',
    ).submitFeedback(contentId: 'c1', rating: HumorRating.funny);

    expect(result.failureOrNull?.message, contains('failed-precondition'));
  });

  test('an expired session is reported as one', () async {
    final result = await _repository(
      'unauthenticated',
    ).skipContent(contentId: 'c1');

    final failure = result.failureOrNull;
    expect(failure, isA<AuthFailure>());
    final auth = failure! as AuthFailure;
    expect(auth.kind, AuthErrorKind.sessionExpired);
    expect(auth.code, 'unauthenticated');
  });
}
