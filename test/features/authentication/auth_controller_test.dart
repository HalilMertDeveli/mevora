import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/restored_session_check.dart';
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

  group('after sign-out, a session started outside the controller', () {
    const userA = AuthUser(
      id: 'user-a',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    const userB = AuthUser(
      id: 'user-b',
      onboardingCompleted: true,
      profileCompleted: true,
    );

    Future<void> signedInAsA() async {
      authRepository.user = userA;
      documents.complete = true;
      controller.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, isA<Authenticated>());
    }

    // The regression: the sign-out flag was never cleared, so a session that
    // reached Firebase without the controller (the emulator QA shortcut, a
    // custom token) was ignored and the app sat on the login page.
    test('for a different account is accepted', () async {
      await signedInAsA();
      await controller.signOut();
      expect(controller.status, isA<Unauthenticated>());

      authRepository.emit(userB);
      await Future<void>.delayed(Duration.zero);

      final status = controller.status;
      expect(status, isA<Authenticated>());
      expect((status as Authenticated).user.id, 'user-b');
      expect(controller.user?.id, 'user-b');
    });

    test(
      'for a different account is accepted after account deletion',
      () async {
        await signedInAsA();
        await controller.deleteAccount();

        authRepository.emit(userB);
        await Future<void>.delayed(Duration.zero);

        expect(controller.user?.id, 'user-b');
        expect(controller.status, isA<Authenticated>());
      },
    );

    test(
      'for the same account is accepted once a sign-in was started',
      () async {
        await signedInAsA();
        await controller.signOut();

        controller.beginExternalSignIn();
        authRepository.emit(userA);
        await Future<void>.delayed(Duration.zero);

        expect(controller.status, isA<Authenticated>());
        expect(controller.user?.id, 'user-a');
      },
    );

    test('still ignores a late echo of the account being signed out', () async {
      await signedInAsA();
      authRepository.signOutDelay = const Duration(milliseconds: 30);

      final pending = controller.signOut();
      // A users/{uid} snapshot of A landing while the sign-out runs.
      authRepository.emit(userA);
      await Future<void>.delayed(Duration.zero);
      controller.beginExternalSignIn(); // ignored: a sign-out is in flight
      await pending;
      authRepository.emit(userA);
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, isA<Unauthenticated>());
      expect(controller.user, isNull);
    });
  });

  // Found in the final acceptance run: an account deleted on the server while
  // the device kept its cached session came back as a "zombie" — the app
  // re-created users/{uid} and profiles/{uid} on the next launch.
  group('a restored session whose account document is missing', () {
    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('creates nothing and ends signed out when the account is gone', () async {
      authRepository
        ..restoredPendingUid = 'deleted-1'
        ..restoredSessionCheck = RestoredSessionCheck.sessionClosed;

      controller.start();
      await settle();

      expect(authRepository.verifiedSessions, ['deleted-1']);
      expect(documents.ensureCalls, 0);
      expect(controller.status, isA<Unauthenticated>());
      expect(controller.user, isNull);
      // Nothing went wrong from the member's side: no banner on sign-in.
      expect(controller.errorMessage, isNull);
      expect(controller.errorKind, isNull);
    });

    test('creates the document when the account still exists', () async {
      authRepository.restoredPendingUid = 'user-1';

      controller.start();
      await settle();

      expect(authRepository.verifiedSessions, ['user-1']);
      expect(documents.ensureCalls, 1);
      expect(documents.ensured?.id, 'user-1');
      expect(controller.status, isA<Authenticating>());
      expect(authRepository.signOutCalls, 0);
    });

    test(
      'creates nothing and keeps the session when the check cannot run',
      () async {
        authRepository
          ..restoredPendingUid = 'user-1'
          ..restoredSessionCheck = RestoredSessionCheck.unverified;

        controller.start();
        await settle();

        expect(documents.ensureCalls, 0);
        // Offline is not a reason to lose the session: the next launch with
        // a connection checks again.
        expect(authRepository.signOutCalls, 0);
        expect(authRepository.signedOut, isFalse);
        // The sign-in screen stays usable instead of a spinner.
        expect(controller.status, isA<AuthenticationError>());
        expect(controller.errorMessage, isNotNull);
        expect(controller.user, isNull);
      },
    );

    test('is not checked during an explicit sign-in', () async {
      controller.start();
      await settle();
      authRepository
        ..googleDelay = const Duration(milliseconds: 30)
        ..restoredSessionCheck = RestoredSessionCheck.sessionClosed;

      final signIn = controller.signInWithGoogle();
      // Firebase has the session, the sign-in flow has not written the
      // document yet.
      authRepository.emitPending('google-1');
      await settle();
      final result = await signIn;

      expect(result, isA<Success<void>>());
      expect(authRepository.verifiedSessions, isEmpty);
      // The flow creates the document itself; the controller adds nothing.
      expect(documents.ensureCalls, 0);
      expect(controller.status, isA<NeedsOnboarding>());
      expect(controller.user?.id, 'google-1');
    });

    test('is not checked while the same process deletes the account', () async {
      const user = AuthUser(
        id: 'user-1',
        onboardingCompleted: true,
        profileCompleted: true,
      );
      authRepository.user = user;
      documents.complete = true;
      controller.start();
      await settle();
      expect(controller.status, isA<Authenticated>());

      var signedOutTransitions = 0;
      var wasSignedOut = false;
      controller.addListener(() {
        final isSignedOut = controller.status is Unauthenticated;
        if (isSignedOut && !wasSignedOut) {
          signedOutTransitions += 1;
        }
        wasSignedOut = isSignedOut;
      });

      authRepository.signOutDelay = const Duration(milliseconds: 30);
      final deletion = controller.deleteAccount();
      // The server deletes users/{uid} before the call returns.
      authRepository.emitPending('user-1');
      await settle();
      final result = await deletion;
      await settle();

      expect(result, isA<Success<void>>());
      expect(authRepository.verifiedSessions, isEmpty);
      expect(documents.ensureCalls, 0);
      expect(controller.status, isA<Unauthenticated>());
      expect(controller.user, isNull);
      expect(controller.errorMessage, isNull);
      expect(signedOutTransitions, 1);
    });
  });

  // The server deletes the documents first and the Auth account last, so a
  // session that watches its document disappear (the account is being
  // deleted from another device, or the app was restarted mid-deletion) can
  // still be told "the account exists" for a moment.
  group('an account document that disappears under a running session', () {
    const user = AuthUser(
      id: 'user-1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    const settleDelay = Duration(milliseconds: 20);
    late AuthController waiting;

    setUp(() {
      waiting = AuthController(
        authRepository: authRepository,
        userDocumentRepository: documents,
        logger: const AppLogger(environment: AppEnvironment.development),
        deletedAccountSettleDelay: settleDelay,
      );
    });

    tearDown(() => waiting.dispose());

    Future<void> signedIn() async {
      authRepository.user = user;
      documents.complete = true;
      waiting.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(waiting.status, isA<Authenticated>());
    }

    test('is not re-created while the deletion may still be running', () async {
      await signedIn();
      authRepository.restoredSessionChecks.addAll([
        RestoredSessionCheck.accountExists,
        RestoredSessionCheck.sessionClosed,
      ]);

      authRepository.emitPending('user-1');
      await Future<void>.delayed(Duration.zero);
      // The first answer alone must not be trusted.
      expect(authRepository.verifiedSessions, ['user-1']);
      expect(documents.ensureCalls, 0);

      await Future<void>.delayed(settleDelay * 3);

      expect(authRepository.verifiedSessions, ['user-1', 'user-1']);
      expect(documents.ensureCalls, 0);
      expect(waiting.status, isA<Unauthenticated>());
      expect(waiting.user, isNull);
      expect(waiting.errorMessage, isNull);
    });

    test('is re-created once the account is confirmed to be still there', () async {
      await signedIn();

      authRepository.emitPending('user-1');
      await Future<void>.delayed(settleDelay * 3);

      expect(authRepository.verifiedSessions, ['user-1', 'user-1']);
      expect(documents.ensureCalls, 1);
      expect(documents.ensured?.id, 'user-1');
      expect(authRepository.signOutCalls, 0);
    });

    test('ends at once when the account is already gone', () async {
      await signedIn();
      authRepository.restoredSessionCheck = RestoredSessionCheck.sessionClosed;

      authRepository.emitPending('user-1');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(authRepository.verifiedSessions, ['user-1']);
      expect(documents.ensureCalls, 0);
      expect(waiting.status, isA<Unauthenticated>());
    });
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
