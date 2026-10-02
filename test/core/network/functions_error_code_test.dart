import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/network/functions_error_code.dart';
import 'package:mevora/features/authentication/data/services/account_deletion_service.dart';
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';

/// The status names of a callable, as the Android SDK reports them.
const _statusNames = [
  'OK',
  'CANCELLED',
  'UNKNOWN',
  'INVALID_ARGUMENT',
  'DEADLINE_EXCEEDED',
  'NOT_FOUND',
  'ALREADY_EXISTS',
  'PERMISSION_DENIED',
  'RESOURCE_EXHAUSTED',
  'FAILED_PRECONDITION',
  'ABORTED',
  'OUT_OF_RANGE',
  'UNIMPLEMENTED',
  'INTERNAL',
  'UNAVAILABLE',
  'DATA_LOSS',
  'UNAUTHENTICATED',
];

/// What cloud_functions on Android makes of a status name on a phone set to
/// Turkish: `lowercase(Locale.getDefault())` turns "I" into the dotless "ı".
String _onATurkishPhone(String statusName) {
  return statusName
      .replaceAll('_', '-')
      .replaceAll('I', 'ı')
      .toLowerCase();
}

FirebaseFunctionsException _error(String code, {Object? details}) {
  // ignore: invalid_use_of_protected_member
  return FirebaseFunctionsException(
    code: code,
    message: 'from-server',
    details: details,
  );
}

class _FakeResult<T> extends Fake implements HttpsCallableResult<T> {
  _FakeResult(this.data);

  @override
  final T data;
}

/// Fails with each of [errors] in turn, then answers with an empty payload.
class _FakeCallable extends Fake implements HttpsCallable {
  _FakeCallable(this.errors);

  final List<Object> errors;
  int calls = 0;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    calls += 1;
    if (errors.isNotEmpty) {
      throw errors.removeAt(0);
    }
    return _FakeResult<T>(<String, dynamic>{'ok': true} as T);
  }
}

class _FakeFunctions extends Fake implements FirebaseFunctions {
  _FakeFunctions(List<Object> errors) : callable = _FakeCallable(errors);

  final _FakeCallable callable;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return callable;
  }
}

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'u1';

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'token';
}

class _FakeAuth extends Fake implements FirebaseAuth {
  _FakeAuth([this.user]);

  final User? user;

  @override
  User? get currentUser => user;
}

class _FakeGoogleSignIn extends Fake implements GoogleSignIn {}

void main() {
  group('canonicalFunctionsErrorCode', () {
    test('reads every status the way a Turkish phone reports it', () {
      for (final name in _statusNames) {
        final canonical = name.replaceAll('_', '-').toLowerCase();
        expect(
          canonicalFunctionsErrorCode(_onATurkishPhone(name)),
          canonical,
          reason: name,
        );
      }
    });

    test('the Turkish form really differs for the codes the app checks', () {
      // Guards the test itself: if these were equal there would be nothing
      // to canonicalise and the cases below would prove nothing.
      expect(_onATurkishPhone('FAILED_PRECONDITION'), 'faıled-precondıtıon');
      expect(_onATurkishPhone('UNAUTHENTICATED'), 'unauthentıcated');
    });

    test('leaves a canonical code alone', () {
      for (final name in _statusNames) {
        final canonical = name.replaceAll('_', '-').toLowerCase();
        expect(canonicalFunctionsErrorCode(canonical), canonical);
      }
    });
  });

  group('canonicalFunctionsError', () {
    test('keeps the message and the details', () {
      final error = canonicalFunctionsError(
        _error('faıled-precondıtıon', details: {'mevoraCode': 'underage'}),
      );

      expect(error.code, 'failed-precondition');
      expect(error.message, 'from-server');
      expect(error.details, {'mevoraCode': 'underage'});
    });

    test('hands back the same error when the code is already canonical', () {
      final original = _error('permission-denied');

      expect(canonicalFunctionsError(original), same(original));
    });
  });

  group('withCanonicalFunctionsErrors', () {
    test('rethrows a callable failure with the canonical code', () async {
      await expectLater(
        withCanonicalFunctionsErrors<void>(
          () async => throw _error('permıssıon-denıed'),
        ),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });

    test('lets other failures and results through untouched', () async {
      final failure = StateError('not a callable error');

      await expectLater(
        withCanonicalFunctionsErrors<void>(() async => throw failure),
        throwsA(same(failure)),
      );
      expect(await withCanonicalFunctionsErrors(() async => 7), 7);
    });
  });

  group('on a phone set to Turkish', () {
    test('a stale token is still retried once', () async {
      final functions = _FakeFunctions([_error('unauthentıcated')]);
      final callable = FirebaseFunctionsCallable(
        functions: functions,
        auth: _FakeAuth(_FakeUser()),
      );

      final payload = await callable.invoke('anything');

      expect(payload, {'ok': true});
      expect(functions.callable.calls, 2);
    });

    test('callers see the code they compare against', () async {
      final functions = _FakeFunctions([_error('faıled-precondıtıon')]);
      final callable = FirebaseFunctionsCallable(
        functions: functions,
        auth: _FakeAuth(),
      );

      await expectLater(
        callable.invoke('anything'),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'failed-precondition',
          ),
        ),
      );
    });

    test('a failed retry is canonical too', () async {
      final functions = _FakeFunctions([
        _error('unauthentıcated'),
        _error('unavaılable'),
      ]);
      final callable = FirebaseFunctionsCallable(
        functions: functions,
        auth: _FakeAuth(),
      );

      await expectLater(
        callable.invoke('anything'),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
    });

    test('account deletion still asks for a fresh sign-in', () async {
      // deleteUserAccount answers failed-precondition when the session is
      // too old. Missing that code sent the member to "Something went wrong"
      // instead of the sign-in-again step.
      final auth = _FakeAuth(_FakeUser());
      final deletion = AccountDeletionService(
        config: const AppConfig(environment: AppEnvironment.development),
        googleAuthService: GoogleAuthService(
          serverClientId: '',
          googleSignIn: _FakeGoogleSignIn(),
          firebaseAuth: auth,
        ),
        functions: _FakeFunctions([_error('faıled-precondıtıon')]),
        firebaseAuth: auth,
      );

      await expectLater(
        deletion.deleteAccount(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.kind,
            'kind',
            AuthErrorKind.oauth,
          ),
        ),
      );
    });
  });
}
