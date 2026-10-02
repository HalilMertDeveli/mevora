import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/datasources/user_remote_datasource.dart';
import 'package:mevora/features/authentication/data/models/user_document.dart';
import 'package:mevora/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:mevora/features/authentication/data/services/account_deletion_service.dart';
import 'package:mevora/features/authentication/data/services/apple_auth_service.dart';
import 'package:mevora/features/authentication/data/services/email_auth_service.dart';
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';
import 'package:mevora/features/authentication/data/services/phone_auth_service.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/restored_session_check.dart';

const _config = AppConfig(environment: AppEnvironment.development);
const _uid = 'u1';

class _FakeUser extends Fake implements User {
  _FakeUser(this.uid);

  @override
  final String uid;

  int reloadCalls = 0;

  /// Runs inside `reload()`; throw from it to fail the call.
  void Function()? onReload;

  @override
  Future<void> reload() async {
    reloadCalls += 1;
    onReload?.call();
  }
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  _FakeFirebaseAuth([this.user]);

  _FakeUser? user;
  final List<String> log = [];
  int signOutCalls = 0;

  @override
  User? get currentUser => user;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    user = null;
    log.add('signOut');
  }
}

class _FakeGoogleSignIn extends Fake implements GoogleSignIn {}

class _RecordingGoogle extends GoogleAuthService {
  _RecordingGoogle(_FakeFirebaseAuth auth)
    : _log = auth.log,
      super(
        serverClientId: '',
        googleSignIn: _FakeGoogleSignIn(),
        firebaseAuth: auth,
      );

  final List<String> _log;
  Object? signOutError;

  @override
  Future<void> signOut() async {
    _log.add('google');
    final error = signOutError;
    if (error != null) {
      throw error;
    }
  }
}

class _FakeCallableResult<T> extends Fake implements HttpsCallableResult<T> {
  _FakeCallableResult(this.data);

  @override
  final T data;
}

class _FakeCallable extends Fake implements HttpsCallable {
  _FakeCallable(this._functions);

  final _FakeFunctions _functions;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    _functions.log.add('server');
    return _FakeCallableResult<T>(_functions.response as T);
  }
}

class _FakeFunctions extends Fake implements FirebaseFunctions {
  _FakeFunctions(this.log);

  final List<String> log;
  Map<String, dynamic> response = {'ok': true, 'deleted': true};

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _FakeCallable(this);
  }
}

class _UnusedUserRemote implements UserRemoteDataSource {
  int writes = 0;

  @override
  Future<AuthUser> upsertFromSession(AuthSession session) async {
    writes += 1;
    return AuthUser(id: session.uid);
  }

  @override
  Future<AuthUser> fetchUser(String uid) async => AuthUser(id: uid);

  @override
  Future<AuthUser?> findUser(String uid) async => null;

  @override
  Stream<UserDocument?> watchUser(String uid) => const Stream.empty();
}

/// The auth data layer over a fake Firebase session, with every local
/// clean-up step recorded in [log] in the order it ran.
class _Harness {
  _Harness({bool signedIn = true})
    : auth = _FakeFirebaseAuth(signedIn ? _FakeUser(_uid) : null) {
    functions = _FakeFunctions(log);
    google = _RecordingGoogle(auth);
    deletion = AccountDeletionService(
      config: _config,
      googleAuthService: google,
      functions: functions,
      firebaseAuth: auth,
      onAccountDeleted: (uid) async {
        log.add('dropKey:$uid');
        final error = dropKeyError;
        if (error != null) {
          throw error;
        }
      },
    );
    repository = AuthRepositoryImpl(
      emailAuthService: EmailAuthService(firebaseAuth: auth),
      googleAuthService: google,
      appleAuthService: AppleAuthService(firebaseAuth: auth),
      spotifyAuthService: SpotifyAuthService(
        config: _config,
        firebaseAuth: auth,
        callbackLinks: const Stream<Uri>.empty(),
      ),
      phoneAuthService: PhoneAuthService(firebaseAuth: auth),
      userRemoteDataSource: remote,
      accountDeletionService: deletion,
      firebaseAuth: auth,
      onBeforeSignOut: (uid) async => log.add('unregisterDevice:$uid'),
      onAfterSignOut: () async => log.add('wipeCache'),
    );
  }

  final _FakeFirebaseAuth auth;
  final remote = _UnusedUserRemote();
  late final _FakeFunctions functions;
  late final _RecordingGoogle google;
  late final AccountDeletionService deletion;
  late final AuthRepositoryImpl repository;
  Object? dropKeyError;

  List<String> get log => auth.log;
  _FakeUser get user => auth.user!;

  void failReload(String code, [String? message]) {
    user.onReload = () =>
        throw FirebaseAuthException(code: code, message: message);
  }
}

void main() {
  group('verifyRestoredSession', () {
    test('an existing account is left alone', () async {
      final h = _Harness();

      final check = await h.repository.verifyRestoredSession(_uid);

      expect(check, RestoredSessionCheck.accountExists);
      expect(h.user.reloadCalls, 1);
      expect(h.log, isEmpty);
      expect(h.auth.currentUser?.uid, _uid);
    });

    test(
      'a deleted account is cleared from the device like a deletion',
      () async {
        final h = _Harness()..failReload('user-not-found');

        final check = await h.repository.verifyRestoredSession(_uid);

        expect(check, RestoredSessionCheck.sessionClosed);
        // The chat key goes with the account; the cache as after any sign-out.
        expect(h.log, ['dropKey:$_uid', 'google', 'signOut', 'wipeCache']);
        expect(h.auth.currentUser, isNull);
        expect(h.remote.writes, 0);
      },
    );

    test('a failing clean-up step still signs a deleted account out', () async {
      final h = _Harness()
        ..failReload('user-not-found')
        ..dropKeyError = StateError('secure storage unavailable');
      h.google.signOutError = StateError('play services unavailable');

      final check = await h.repository.verifyRestoredSession(_uid);

      expect(check, RestoredSessionCheck.sessionClosed);
      expect(h.auth.signOutCalls, 1);
      expect(h.auth.currentUser, isNull);
    });

    for (final code in const [
      'user-disabled',
      'user-token-expired',
      'invalid-user-token',
    ]) {
      test(
        'a revoked session ($code) is signed out and keeps the chat key',
        () async {
          final h = _Harness()..failReload(code);

          final check = await h.repository.verifyRestoredSession(_uid);

          expect(check, RestoredSessionCheck.sessionClosed);
          // The account can come back, and with it the conversations only
          // this key can read.
          expect(h.log, [
            'unregisterDevice:$_uid',
            'google',
            'signOut',
            'wipeCache',
          ]);
          expect(h.auth.currentUser, isNull);
        },
      );
    }

    test('a failed check changes nothing', () async {
      final h = _Harness()..failReload('network-request-failed');

      final check = await h.repository.verifyRestoredSession(_uid);

      expect(check, RestoredSessionCheck.unverified);
      expect(h.log, isEmpty);
      expect(h.auth.currentUser?.uid, _uid);
    });

    test('an error that is not an auth error changes nothing', () async {
      final h = _Harness();
      h.user.onReload = () => throw TimeoutException('reload');

      final check = await h.repository.verifyRestoredSession(_uid);

      expect(check, RestoredSessionCheck.unverified);
      expect(h.log, isEmpty);
      expect(h.auth.currentUser?.uid, _uid);
    });

    test('no session is a closed session', () async {
      final h = _Harness(signedIn: false);

      final check = await h.repository.verifyRestoredSession(_uid);

      expect(check, RestoredSessionCheck.sessionClosed);
      expect(h.log, isEmpty);
    });

    test('another account\'s session is not touched', () async {
      final h = _Harness();

      final check = await h.repository.verifyRestoredSession('someone-else');

      expect(check, RestoredSessionCheck.sessionClosed);
      expect(h.user.reloadCalls, 0);
      expect(h.log, isEmpty);
      expect(h.auth.currentUser?.uid, _uid);
    });

    test('a session signed out while the check ran is closed', () async {
      // The resume-time recovery signs a revoked session out on its own.
      final h = _Harness();
      final user = h.user;
      user.onReload = () {
        h.auth.user = null;
        throw FirebaseAuthException(code: 'no-current-user');
      };

      final check = await h.repository.verifyRestoredSession(_uid);

      expect(check, RestoredSessionCheck.sessionClosed);
      expect(h.log, isEmpty);
    });
  });

  group('deleting the account from this device', () {
    test('signs out locally only after the server confirmed', () async {
      final h = _Harness();

      final result = await h.repository.deleteAccount();

      expect(result.isSuccess, isTrue);
      expect(h.log, [
        'server',
        'dropKey:$_uid',
        'google',
        'signOut',
        'wipeCache',
      ]);
    });

    test('stays signed in when the server did not confirm', () async {
      final h = _Harness();
      h.functions.response = {'ok': false, 'deleted': false, 'code': 'busy'};

      await expectLater(
        h.deletion.deleteAccount(),
        throwsA(isA<AuthException>()),
      );

      expect(h.log, ['server']);
      expect(h.auth.currentUser?.uid, _uid);
    });

    test('a failing clean-up step cannot leave the device signed in', () async {
      final h = _Harness()
        ..dropKeyError = StateError('secure storage unavailable');
      h.google.signOutError = StateError('play services unavailable');

      await h.deletion.deleteAccount();

      expect(h.auth.signOutCalls, 1);
      expect(h.auth.currentUser, isNull);
    });
  });
}
