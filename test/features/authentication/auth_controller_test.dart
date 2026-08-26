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
    expect(controller.user?.id, 'user-1');
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

  test('logout failure keeps the session and does not throw', () async {
    authRepository.user = const AuthUser(
      id: 'user-1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    documents.complete = true;
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    authRepository.nextFailure = const AuthFailure(
      'We could not complete that request. Please try again.',
    );

    final result = await controller.signOut();

    expect(result, isA<Err<void>>());
    expect(controller.status, isA<Authenticated>());
    expect(controller.user?.id, 'user-1');
    expect(controller.errorMessage, isNotNull);
    expect(authRepository.signedOut, isFalse);
  });

  test('double-tap logout is ignored', () async {
    authRepository.user = const AuthUser(
      id: 'user-1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    documents.complete = true;
    authRepository.signOutDelay = const Duration(milliseconds: 40);
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final first = controller.signOut();
    final second = controller.signOut();
    await Future.wait<Result<void>>([first, second]);

    expect(authRepository.signOutCalls, 1);
    expect(controller.status, isA<Unauthenticated>());
    expect(controller.user, isNull);
  });

  test('stale profile snapshot after logout is ignored', () async {
    const user = AuthUser(
      id: 'user-1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    authRepository.user = user;
    documents.complete = true;
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.signOut();
    authRepository.emit(user);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, isA<Unauthenticated>());
    expect(controller.user, isNull);
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

  test('register with email succeeds for a new account', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final result = await controller.register(
      email: ' ada@mevora.app ',
      password: 'password1',
    );

    expect(result, isA<Success<void>>());
    expect(authRepository.registerCalls, 1);
    expect(authRepository.lastEmail, 'ada@mevora.app');
    expect(authRepository.passwordSubmitted, isTrue);
  });

  test('register surfaces email-already-in-use without raw firebase text', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    authRepository.nextFailure = const AuthFailure(
      'An account already exists for that email.',
      kind: AuthErrorKind.emailInUse,
    );

    final result = await controller.register(
      email: 'ada@mevora.app',
      password: 'password1',
    );

    expect(result, isA<Err<void>>());
    expect(controller.errorKind, AuthErrorKind.emailInUse);
    expect(controller.errorMessage?.toLowerCase().contains('firebase'), isFalse);
  });

  test('password reset hides whether the email exists', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    authRepository.nextFailure = const AuthFailure(
      'No account found for that email.',
      kind: AuthErrorKind.userNotFound,
    );

    final result = await controller.sendPasswordReset('ada@mevora.app');

    expect(result, isA<Success<void>>());
    expect(controller.errorKind, isNull);
    expect(controller.errorMessage, isNull);
    expect(authRepository.lastResetEmail, 'ada@mevora.app');
  });

  test('link email records the provider on the current account', () async {
    authRepository.user = const AuthUser(
      id: 'user-1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    documents.complete = true;
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final result = await controller.linkEmail(
      email: 'ada@mevora.app',
      password: 'password1',
    );

    expect(result, isA<Success<void>>());
    expect(authRepository.lastLinkedProvider, AuthProviderId.email);
    expect(authRepository.user?.authProviders.email, isTrue);
    expect(controller.status, isA<Authenticated>());
  });

  test('invalid otp stays on verification with a Turkish error', () async {
    controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.sendPhoneCode('+905551112242');
    expect(controller.status, isA<PhoneCodeSent>());

    await controller.verifyPhoneCode('000000');

    expect(controller.status, isA<PhoneVerificationRequired>());
    expect(controller.errorMessage, 'Doğrulama kodu hatalı.');
  });
}
