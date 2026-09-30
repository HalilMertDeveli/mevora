import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/data/datasources/firebase_user_data_source.dart';
import 'package:mevora/features/authentication/data/models/user_document.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';

import '../../helpers/fake_auth.dart';

const _active = AuthUser(
  id: 'user-1',
  email: 'ada@mevora.app',
  profileCompleted: true,
  onboardingCompleted: true,
);

final _suspended = _active.copyWith(
  isActive: false,
  accountStatus: AccountStatus.suspended,
  suspendedUntil: DateTime.utc(2030, 1, 1),
);

final _banned = _active.copyWith(
  isActive: false,
  isBanned: true,
  accountStatus: AccountStatus.banned,
);

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('auth controller', () {
    late FakeAuthRepository authRepository;
    late AuthController controller;

    setUp(() {
      authRepository = FakeAuthRepository();
      controller = AuthController(
        authRepository: authRepository,
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
      );
    });

    tearDown(() {
      controller.dispose();
      authRepository.dispose();
    });

    test('a suspended member stays signed in, restricted', () async {
      authRepository.user = _suspended;
      controller.start();
      await _settle();

      expect(authRepository.signOutCalls, 0);
      final status = controller.status;
      expect(status, isA<Authenticated>());
      expect((status as Authenticated).user.isSuspended, isTrue);
      expect(controller.user?.suspendedUntil, DateTime.utc(2030, 1, 1));
      expect(controller.errorKind, isNull);
    });

    test('suspension arriving mid-session keeps the session', () async {
      authRepository.user = _active;
      controller.start();
      await _settle();
      expect(controller.user?.isSuspended, isFalse);

      authRepository.emit(_suspended);
      await _settle();

      expect(authRepository.signOutCalls, 0);
      expect(controller.user?.isSuspended, isTrue);
      expect(controller.status, isA<Authenticated>());
    });

    test('a banned member is signed out with the banned message', () async {
      authRepository.user = _active;
      controller.start();
      await _settle();

      authRepository.emit(_banned);
      await _settle();

      expect(authRepository.signOutCalls, 1);
      expect(controller.user, isNull);
      expect(controller.errorKind, AuthErrorKind.banned);
      expect(controller.status, isNot(isA<Authenticated>()));
    });

    test('a disabled (legacy inactive) account is still signed out', () async {
      authRepository.user = _active.copyWith(
        isActive: false,
        accountStatus: AccountStatus.disabled,
      );
      controller.start();
      await _settle();

      expect(authRepository.signOutCalls, 1);
      expect(controller.errorKind, AuthErrorKind.banned);
    });

    test('restoring the account releases the member', () async {
      authRepository.user = _suspended;
      controller.start();
      await _settle();
      expect(controller.user?.isSuspended, isTrue);

      authRepository.emit(_active);
      await _settle();

      expect(authRepository.signOutCalls, 0);
      final status = controller.status;
      expect(status, isA<Authenticated>());
      expect((status as Authenticated).user.isSuspended, isFalse);
      expect(status.user.accountStatus, AccountStatus.active);
    });
  });

  group('sign-in gate', () {
    test('lets a suspended member in, refuses banned and disabled', () {
      expect(
        () => FirebaseUserDataSource.ensureSignInAllowed(_suspended),
        returnsNormally,
      );
      expect(
        () => FirebaseUserDataSource.ensureSignInAllowed(_active),
        returnsNormally,
      );
      expect(
        () => FirebaseUserDataSource.ensureSignInAllowed(_banned),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.banned,
          ),
        ),
      );
      expect(
        () => FirebaseUserDataSource.ensureSignInAllowed(
          _active.copyWith(
            isActive: false,
            accountStatus: AccountStatus.deleted,
          ),
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('signing in never rewrites server-owned status fields', () {
      final source = File(
        'lib/features/authentication/data/datasources/firebase_user_data_source.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final start = source.indexOf('Map<String, dynamic> _accountUpdates(');
      final end = source.indexOf('Map<String, dynamic> _newProfileStub(');
      expect(start, greaterThan(0));
      final updates = source.substring(start, end);
      for (final field in const [
        'accountStatus',
        'isSuspended',
        'suspendedUntil',
        'isBanned',
        'statusReasonCode',
      ]) {
        expect(
          updates.contains("'$field'"),
          isFalse,
          reason: 'sign-in must not write $field over the server value',
        );
      }
    });
  });

  group('account document', () {
    UserDocument read(Map<String, dynamic> account) =>
        UserDocument.fromAccountAndProfile(
          uid: 'u1',
          account: account,
          profile: const {},
        );

    test('carries the suspension and its end into the user', () {
      final until = DateTime.now().add(const Duration(days: 2));
      final user = read({
        'accountStatus': 'suspended',
        'isSuspended': true,
        'suspendedUntil': until,
      }).toEntity();

      expect(user.accountStatus, AccountStatus.suspended);
      expect(user.isSuspended, isTrue);
      expect(user.suspendedUntil, until);
      expect(user.isActive, isFalse);
    });

    test('an expired suspension is active with no end date', () {
      final user = read({
        'accountStatus': 'suspended',
        'isSuspended': true,
        'suspendedUntil': DateTime.now().subtract(const Duration(minutes: 1)),
      }).toEntity();

      expect(user.accountStatus, AccountStatus.active);
      expect(user.isSuspended, isFalse);
      expect(user.suspendedUntil, isNull);
    });

    test('a restore on the account document reaches the live user', () async {
      final account = StreamController<Map<String, dynamic>?>();
      final profile = StreamController<Map<String, dynamic>>();
      final emitted = <UserDocument?>[];
      final sub = FirebaseUserDataSource.watchAccountAndProfile(
        uid: 'u1',
        account: account.stream,
        profile: profile.stream,
      ).listen(emitted.add);

      account.add({'accountStatus': 'suspended', 'isSuspended': true});
      profile.add(const {});
      await pumpEventQueue();
      account.add({'accountStatus': 'active', 'isSuspended': false});
      await pumpEventQueue();

      expect(emitted.map((doc) => doc?.accountStatus), [
        AccountStatus.suspended,
        AccountStatus.active,
      ]);
      await sub.cancel();
      await account.close();
      await profile.close();
    });
  });
}
