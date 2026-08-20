import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/data/services/auth_analytics.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/pages/login_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

class _RecordingAnalytics implements AuthAnalytics {
  final events = <String>[];

  @override
  Future<void> loginScreenViewed() async => events.add('login_screen_viewed');

  @override
  Future<void> phoneAuthStarted() async => events.add('phone_auth_started');

  @override
  Future<void> otpSent() async => events.add('otp_sent');

  @override
  Future<void> otpVerified() async => events.add('otp_verified');

  @override
  Future<void> phoneAuthFailed() async => events.add('phone_auth_failed');

  @override
  Future<void> otpResend() async => events.add('otp_resend');

  @override
  Future<void> otpVerificationFailed() async =>
      events.add('otp_verification_failed');

  @override
  Future<void> googleLoginStarted() async => events.add('google_login_started');

  @override
  Future<void> googleLoginSuccess() async => events.add('google_login_success');

  @override
  Future<void> googleLoginFailed() async => events.add('google_login_failed');

  @override
  Future<void> googleLoginCancelled() async =>
      events.add('google_login_cancelled');
}

Widget _wrap({required AuthController controller, required Widget child}) {
  const environment = AppEnvironment.development;
  return AppScope(
    config: const AppConfig(environment: environment),
    logger: const AppLogger(environment: environment),
    child: AuthScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      ),
    ),
  );
}

void main() {
  group('Google auth unit', () {
    late FakeAuthRepository authRepository;
    late AuthController controller;
    late _RecordingAnalytics analytics;

    setUp(() {
      authRepository = FakeAuthRepository();
      analytics = _RecordingAnalytics();
      controller = AuthController(
        authRepository: authRepository,
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
        analytics: analytics,
      )..start();
    });

    tearDown(() {
      controller.dispose();
      authRepository.dispose();
    });

    test('never auto-merges accounts by email', () {
      expect(
        AccountLinkingPolicy.shouldAutoMergeByEmail(
          existingEmail: 'ada@mevora.app',
          incomingEmail: 'ada@mevora.app',
        ),
        isFalse,
      );
    });

    test('maps Google cancel and failure without firebase codes', () {
      final cancelled = AuthErrorMapper.fromCode('canceled');
      expect(cancelled.kind, AuthErrorKind.cancelled);
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.message.toLowerCase().contains('firebase'), isFalse);

      final failed = AuthErrorMapper.fromCode('operation-not-allowed');
      expect(failed.kind, AuthErrorKind.notConfigured);

      final network = AuthErrorMapper.fromCode('network-request-failed');
      expect(network.kind, AuthErrorKind.network);

      final clientConfig = AuthErrorMapper.fromCode('clientConfigurationError');
      expect(clientConfig.kind, AuthErrorKind.oauth);
    });

    test('provider detection records Google on linked accounts', () {
      const providers = AuthProviders(phone: true);
      final linked = providers.withProvider(AuthProviderId.google);
      expect(linked.google, isTrue);
      expect(linked.phone, isTrue);
      expect(linked.isLinked(AuthProviderId.google), isTrue);
    });

    test('incomplete Google profile routes to onboarding', () async {
      await Future<void>.delayed(Duration.zero);
      await controller.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(authRepository.googleCalled, isTrue);
      expect(controller.status, isA<NeedsOnboarding>());
      expect(analytics.events, contains('google_login_started'));
      expect(analytics.events, contains('google_login_success'));
      expect(analytics.events.join(), isNot(contains('@')));
    });

    test('complete Google profile reaches authenticated', () async {
      authRepository.googleUser = const AuthUser(
        id: 'google-1',
        email: 'ada@mevora.app',
        profileCompleted: true,
        onboardingCompleted: true,
        authProviders: AuthProviders(google: true),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, isA<Authenticated>());
    });

    test('cancelled Google sign-in stays on login without error', () async {
      await Future<void>.delayed(Duration.zero);
      authRepository.nextFailure = const AuthFailure(
        'cancelled',
        kind: AuthErrorKind.cancelled,
        isCancelled: true,
      );

      await controller.signInWithGoogle();

      expect(controller.errorMessage, isNull);
      expect(controller.errorKind, isNull);
      expect(controller.status, isA<Unauthenticated>());
      expect(analytics.events, contains('google_login_cancelled'));
      expect(analytics.events, isNot(contains('google_login_failed')));
    });

    test('failed Google sign-in records failed analytics', () async {
      await Future<void>.delayed(Duration.zero);
      authRepository.nextFailure = const AuthFailure(
        'Google Sign-In could not be completed.',
        kind: AuthErrorKind.oauth,
      );

      await controller.signInWithGoogle();

      expect(controller.errorKind, AuthErrorKind.oauth);
      expect(analytics.events, contains('google_login_failed'));
    });

    test('logout clears session for Google or phone users', () async {
      authRepository.user = const AuthUser(
        id: 'google-1',
        profileCompleted: true,
        onboardingCompleted: true,
        authProviders: AuthProviders(google: true),
      );
      controller = AuthController(
        authRepository: authRepository,
        userDocumentRepository: FakeUserDocumentRepository(complete: true),
        logger: const AppLogger(environment: AppEnvironment.development),
        analytics: analytics,
      )..start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await controller.signOut();

      expect(controller.status, isA<Unauthenticated>());
      expect(authRepository.signedOut, isTrue);
    });
  });

  group('Google login widget', () {
    late FakeAuthRepository authRepository;
    late AuthController controller;

    setUp(() {
      authRepository = FakeAuthRepository();
      controller = AuthController(
        authRepository: authRepository,
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
      )..start();
    });

    tearDown(() {
      controller.dispose();
      authRepository.dispose();
    });

    testWidgets('tapping Continue with Google calls the repository', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(controller: controller, child: const LoginPage()),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(_l10n.continueWithGoogle));
      await tester.tap(find.text(_l10n.continueWithGoogle));
      await tester.pump();
      await tester.pump();

      expect(authRepository.googleCalled, isTrue);
    });

    testWidgets('Google loading state disables the button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      authRepository.googleDelay = const Duration(milliseconds: 200);
      await tester.pumpWidget(
        _wrap(controller: controller, child: const LoginPage()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_l10n.continueWithGoogle));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(controller.status, isA<Authenticating>());

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
    });

    testWidgets('cancelled Google sign-in shows no error banner', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      authRepository.nextFailure = const AuthFailure(
        'cancelled',
        kind: AuthErrorKind.cancelled,
        isCancelled: true,
      );
      await tester.pumpWidget(
        _wrap(controller: controller, child: const LoginPage()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_l10n.continueWithGoogle));
      await tester.pump();
      await tester.pump();

      expect(find.text(_l10n.authCancelled), findsNothing);
      expect(find.text(_l10n.googleSignInCancelled), findsNothing);
      expect(find.text(_l10n.authGoogleFailed), findsNothing);
    });

    testWidgets('failed Google sign-in shows localized error', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      authRepository.nextFailure = const AuthFailure(
        'oauth',
        kind: AuthErrorKind.oauth,
      );
      await tester.pumpWidget(
        _wrap(controller: controller, child: const LoginPage()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_l10n.continueWithGoogle));
      await tester.pump();
      await tester.pump();

      expect(find.text(_l10n.authGoogleFailed), findsOneWidget);
    });
  });
}
