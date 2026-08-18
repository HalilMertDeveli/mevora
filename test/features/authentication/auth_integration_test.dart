import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';

import '../../helpers/fake_auth.dart';

/// Integration-style coverage with fakes: phone + Google + logout + persistence.
void main() {
  late FakeAuthRepository authRepository;
  late FakeUserDocumentRepository documents;
  late AuthController controller;

  setUp(() {
    authRepository = FakeAuthRepository();
    documents = FakeUserDocumentRepository();
    controller = AuthController(
      authRepository: authRepository,
      userDocumentRepository: documents,
      logger: const AppLogger(environment: AppEnvironment.development),
    )..start();
  });

  tearDown(() {
    controller.dispose();
    authRepository.dispose();
  });

  test('phone then logout then Google keeps a single auth state machine', () async {
    await Future<void>.delayed(Duration.zero);

    await controller.sendPhoneCode('+905551112233');
    expect(controller.status, isA<PhoneCodeSent>());
    expect(controller.phoneChallenge?.verificationId, isNotEmpty);

    await controller.verifyPhoneCode('123456');
    expect(controller.status, isA<Authenticated>());
    expect(controller.user?.id, 'phone-1');

    await controller.signOut();
    expect(controller.status, isA<Unauthenticated>());
    expect(controller.user, isNull);
    expect(authRepository.signedOut, isTrue);

    authRepository.googleUser = const AuthUser(
      id: 'google-1',
      email: 'ada@mevora.app',
      profileCompleted: true,
      onboardingCompleted: true,
      authProviders: AuthProviders(google: true),
    );
    await controller.signInWithGoogle();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, isA<Authenticated>());
    expect(controller.user?.id, 'google-1');
    expect(controller.user?.authProviders.google, isTrue);
  });

  test('auth state does not expose provider-specific UI requirements', () async {
    await Future<void>.delayed(Duration.zero);

    await controller.signInWithGoogle();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, isA<NeedsOnboarding>());
    expect(controller.user?.id, isNotEmpty);

    await controller.signOut();
    expect(controller.status, isA<Unauthenticated>());
  });

  test('persistence: restarting the controller restores profile-ready state', () async {
    authRepository.user = const AuthUser(
      id: 'persisted-1',
      profileCompleted: true,
      onboardingCompleted: true,
      authProviders: AuthProviders(google: true, phone: true),
    );
    documents.complete = true;

    final restarted = AuthController(
      authRepository: authRepository,
      userDocumentRepository: documents,
      logger: const AppLogger(environment: AppEnvironment.development),
    )..start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(restarted.status, isA<Authenticated>());
    expect(restarted.user?.id, 'persisted-1');
    restarted.dispose();
  });

  test('failed phone send then Google success recovers cleanly', () async {
    await Future<void>.delayed(Duration.zero);
    authRepository.sendResult = const Err(
      AuthFailure('SMS failed', kind: AuthErrorKind.smsFailed),
    );

    await controller.sendPhoneCode('+905551112233');
    expect(controller.errorKind, AuthErrorKind.smsFailed);

    authRepository.sendResult = null;
    authRepository.nextFailure = null;
    await controller.signInWithGoogle();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, isA<NeedsOnboarding>());
    expect(authRepository.googleCalled, isTrue);
  });
}
