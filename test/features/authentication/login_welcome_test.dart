import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/services/auth_analytics.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/pages/login_page.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/features/authentication/presentation/widgets/login_hero_background.dart';
import 'package:mevora/features/authentication/presentation/widgets/welcome_auth_buttons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

import '../../helpers/fake_auth.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

class _RecordingAnalytics implements AuthAnalytics {
  final events = <String>[];

  @override
  Future<void> loginScreenViewed() async => events.add('login_screen_viewed');

  @override
  Future<void> phoneAuthStarted() async {}

  @override
  Future<void> otpSent() async {}

  @override
  Future<void> otpVerified() async {}

  @override
  Future<void> phoneAuthFailed() async {}

  @override
  Future<void> otpResend() async {}

  @override
  Future<void> otpVerificationFailed() async {}

  @override
  Future<void> googleLoginStarted() async => events.add('google_login_started');

  @override
  Future<void> googleLoginSuccess() async {}

  @override
  Future<void> googleLoginFailed() async {}

  @override
  Future<void> googleLoginCancelled() async =>
      events.add('google_login_cancelled');
}

Widget _wrap({
  required AuthController controller,
  required Widget child,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  const environment = AppEnvironment.development;
  return AppScope(
    config: const AppConfig(environment: environment),
    logger: const AppLogger(environment: environment),
    child: AuthScope(
      controller: controller,
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      ),
    ),
  );
}

void main() {
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

  Future<void> pumpLogin(WidgetTester tester, {Locale? locale}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrap(
        controller: controller,
        child: const LoginPage(),
        locale: locale ?? const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('welcome screen shows hero, slogan, and the CTAs', (
    tester,
  ) async {
    await pumpLogin(tester);

    expect(find.byType(LoginHeroBackground), findsOneWidget);
    expect(find.byType(WelcomeAuthButtons), findsOneWidget);
    expect(find.text('mevora'), findsOneWidget);
    expect(find.text(_en.loginSlogan), findsOneWidget);
    expect(find.text(_en.continueWithGoogle), findsOneWidget);
    expect(find.text(_en.continueWithPhone), findsOneWidget);
    expect(find.text(_en.continueWithSpotify), findsOneWidget);
    expect(find.text(_en.continueWithEmail), findsOneWidget);
    expect(analytics.events, contains('login_screen_viewed'));
  });

  // Sign in with Apple only runs on Apple platforms, so the button is only
  // offered there: on Android it could never succeed.
  testWidgets(
    'Android does not offer Continue with Apple',
    (tester) async {
      await pumpLogin(tester);

      expect(find.byType(MevoraProviderButton), findsNWidgets(4));
      expect(find.text(_en.continueWithApple), findsNothing);
      expect(find.bySemanticsLabel(_en.continueWithApple), findsNothing);
      // Google stays the emphasized first choice.
      final first = tester.widget<MevoraProviderButton>(
        find.byType(MevoraProviderButton).first,
      );
      expect(first.label, _en.continueWithGoogle);
      expect(first.emphasized, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'iOS offers Continue with Apple first and it starts Apple sign-in',
    (tester) async {
      await pumpLogin(tester);

      expect(find.byType(MevoraProviderButton), findsNWidgets(5));
      expect(find.bySemanticsLabel(_en.continueWithApple), findsOneWidget);
      final first = tester.widget<MevoraProviderButton>(
        find.byType(MevoraProviderButton).first,
      );
      expect(first.label, _en.continueWithApple);
      expect(first.emphasized, isTrue);

      await tester.tap(find.text(_en.continueWithApple));
      await tester.pump();
      await tester.pump();
      expect(authRepository.appleCalled, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'macOS offers Continue with Apple',
    (tester) async {
      await pumpLogin(tester);

      expect(find.text(_en.continueWithApple), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Turkish slogan is localized', (tester) async {
    await pumpLogin(tester, locale: const Locale('tr'));
    expect(find.text(_tr.loginSlogan), findsOneWidget);
    expect(find.text(_tr.continueWithGoogle), findsOneWidget);
  });

  testWidgets('provider buttons have semantics labels', (tester) async {
    await pumpLogin(tester);
    expect(find.bySemanticsLabel(_en.continueWithGoogle), findsOneWidget);
    expect(find.bySemanticsLabel(_en.continueWithPhone), findsOneWidget);
    expect(find.bySemanticsLabel(_en.continueWithSpotify), findsOneWidget);
    expect(find.bySemanticsLabel(_en.continueWithEmail), findsOneWidget);
  });

  testWidgets('Google tap starts auth and shows loading', (tester) async {
    authRepository.googleDelay = const Duration(milliseconds: 200);
    await pumpLogin(tester);

    await tester.tap(find.text(_en.continueWithGoogle));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(controller.status, isA<Authenticating>());
    expect(authRepository.googleCalled, isTrue);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  });

  testWidgets('Google cancel shows no error banner', (tester) async {
    authRepository.nextFailure = const AuthFailure(
      'cancelled',
      kind: AuthErrorKind.cancelled,
      isCancelled: true,
    );
    await pumpLogin(tester);

    await tester.tap(find.text(_en.continueWithGoogle));
    await tester.pump();
    await tester.pump();

    expect(find.text(_en.authCancelled), findsNothing);
    expect(find.text(_en.authGoogleFailed), findsNothing);
    expect(analytics.events, contains('google_login_cancelled'));
  });

  testWidgets('Google failure shows localized error', (tester) async {
    authRepository.nextFailure = const AuthFailure(
      'oauth',
      kind: AuthErrorKind.oauth,
    );
    await pumpLogin(tester);

    await tester.tap(find.text(_en.continueWithGoogle));
    await tester.pump();
    await tester.pump();

    expect(find.text(_en.authGoogleFailed), findsOneWidget);
  });

  testWidgets('email CTA reveals email form', (tester) async {
    await pumpLogin(tester);
    expect(find.text(_en.signIn), findsNothing);

    await tester.tap(find.text(_en.continueWithEmail));
    await tester.pumpAndSettle();

    expect(find.text(_en.signIn), findsOneWidget);
    expect(find.widgetWithText(TextField, _en.email), findsOneWidget);
  });

  testWidgets('login remains readable in dark theme', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        controller: controller,
        child: const LoginPage(),
        theme: AppTheme.dark(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('mevora'), findsOneWidget);
    expect(find.text(_en.loginSlogan), findsOneWidget);
    expect(find.byType(LoginHeroBackground), findsOneWidget);
  });

  testWidgets('small phone layout does not overflow', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(controller: controller, child: const LoginPage()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text(_en.continueWithEmail),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(_en.continueWithEmail), findsOneWidget);
  });

  // The email form sits a full screen below the provider buttons. Its error
  // used to be shown above them, out of sight, so a failed sign-in looked as
  // if nothing had happened.
  testWidgets('a failed email sign-in shows its error inside the email form', (
    tester,
  ) async {
    await pumpLogin(tester);
    final scrollable = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.text(_en.continueWithEmail),
      120,
      scrollable: scrollable,
    );
    await tester.tap(find.text(_en.continueWithEmail));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, _en.email),
      'someone@mevora.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _en.password),
      'wrong-password-1',
    );
    authRepository.nextFailure = const AuthFailure(
      'wrong-password',
      kind: AuthErrorKind.wrongPassword,
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(MevoraButton, _en.signIn),
      120,
      scrollable: scrollable,
    );
    await tester.tap(find.widgetWithText(MevoraButton, _en.signIn));
    await tester.pumpAndSettle();

    final banner = find.byType(AuthErrorBanner);
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: find.byType(MevoraCard), matching: banner),
      findsOneWidget,
    );
    expect(find.text(_en.authWrongPassword), findsOneWidget);
  });
}
