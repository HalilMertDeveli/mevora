import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';

import '../../helpers/fake_auth.dart';

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
    );
  });

  tearDown(() {
    controller.dispose();
    authRepository.dispose();
  });

  test('starts unauthenticated when there is no session', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, isA<Unauthenticated>());
    expect(controller.user, isNull);
  });

  test('missing profile is treated as onboarding', () async {
    authRepository.user = const AuthUser(id: 'user-1', email: 'ada@mevora.app');
    documents.complete = false;
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, isA<NeedsOnboarding>());
    expect(documents.ensured?.id, 'user-1');
  });

  test('complete profile reaches authenticated status', () async {
    authRepository.user = const AuthUser(
      id: 'user-1',
      email: 'ada@mevora.app',
      profileCompleted: true,
      onboardingCompleted: true,
    );
    documents.complete = true;
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, isA<Authenticated>());
  });

  test('sign-in failure surfaces a message', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    authRepository.nextFailure = const AuthFailure(
      'That email and password combination does not match.',
      kind: AuthErrorKind.wrongPassword,
    );

    final result = await controller.signIn(
      email: 'ada@mevora.app',
      password: 'wrong-pass',
    );

    expect(result, isA<Err<void>>());
    expect(
      controller.errorMessage,
      'That email and password combination does not match.',
    );
  });

  test('cancelled social sign-in does not set an error', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    authRepository.nextFailure = const AuthFailure(
      'cancelled',
      kind: AuthErrorKind.cancelled,
      isCancelled: true,
    );

    await controller.signInWithGoogle();

    expect(controller.errorMessage, isNull);
  });

  test('logout returns to unauthenticated', () async {
    authRepository.user = const AuthUser(
      id: 'user-1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    documents.complete = true;
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.signOut();

    expect(controller.status, isA<Unauthenticated>());
    expect(controller.user, isNull);
    expect(authRepository.signedOut, isTrue);
  });

  test('explicit linking records the provider and does not auto-merge', () async {
    authRepository.user = const AuthUser(
      id: 'user-1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    documents.complete = true;
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.linkProvider(AuthProviderId.google);

    expect(authRepository.lastLinkedProvider, AuthProviderId.google);
    expect(authRepository.user?.authProviders.google, isTrue);
  });

  test('invalid otp stays on verification with a Turkish error', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.sendPhoneCode('+905551112242');
    expect(controller.status, isA<PhoneCodeSent>());

    await controller.verifyPhoneCode('000000');

    expect(controller.status, isA<PhoneVerificationRequired>());
    expect(controller.errorMessage, 'Doğrulama kodu geçersiz.');
  });
}
