import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/pages/login_page.dart';
import 'package:mevora/features/authentication/presentation/pages/password_reset_page.dart';
import 'package:mevora/features/authentication/presentation/pages/register_page.dart';
import 'package:mevora/features/authentication/presentation/screens/phone_login_screen.dart';
import 'package:mevora/features/authentication/presentation/widgets/otp_code_input.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

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

  testWidgets('login validates empty fields without calling auth', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(controller: controller, child: const LoginPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l10n.continueWithEmail));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(_l10n.signIn));
    await tester.tap(find.text(_l10n.signIn));
    await tester.pump();

    expect(find.text(_l10n.emailRequired), findsOneWidget);
    expect(find.text(_l10n.passwordRequired), findsOneWidget);
    expect(authRepository.user, isNull);
    expect(authRepository.signInCalls, 0);
  });

  testWidgets('login submits email and password through the controller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(controller: controller, child: const LoginPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l10n.continueWithEmail));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, _l10n.email),
      'ada@mevora.app',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.password),
      'password1',
    );
    await tester.ensureVisible(find.text(_l10n.signIn));
    await tester.tap(find.text(_l10n.signIn));
    await tester.pump();
    await tester.pump();

    expect(authRepository.signInCalls, 1);
    expect(authRepository.lastEmail, 'ada@mevora.app');
    expect(authRepository.passwordSubmitted, isTrue);
  });

  testWidgets('login shows a localized wrong-password error', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    authRepository.nextFailure = const AuthFailure(
      'That email and password combination does not match.',
      kind: AuthErrorKind.wrongPassword,
    );
    await tester.pumpWidget(_wrap(controller: controller, child: const LoginPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l10n.continueWithEmail));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, _l10n.email),
      'ada@mevora.app',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.password),
      'wrong-pass',
    );
    await tester.ensureVisible(find.text(_l10n.signIn));
    await tester.tap(find.text(_l10n.signIn));
    await tester.pump();
    await tester.pump();

    expect(find.text(_l10n.authWrongPassword), findsOneWidget);
  });

  testWidgets('register rejects mismatched passwords', (tester) async {
    await tester.pumpWidget(
      _wrap(controller: controller, child: const RegisterPage()),
    );
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, _l10n.email),
      'ada@mevora.app',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.password),
      'password1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.confirmPassword),
      'password2',
    );
    await tester.tap(find.text(_l10n.createAccount));
    await tester.pump();

    expect(find.text(_l10n.passwordsDoNotMatch), findsOneWidget);
    expect(authRepository.registerCalls, 0);
  });

  testWidgets('register submits matching credentials', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(controller: controller, child: const RegisterPage()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, _l10n.email),
      'ada@mevora.app',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.password),
      'password1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.confirmPassword),
      'password1',
    );
    await tester.ensureVisible(find.text(_l10n.createAccount));
    await tester.tap(find.text(_l10n.createAccount));
    await tester.pump();
    await tester.pump();

    expect(authRepository.registerCalls, 1);
    expect(authRepository.lastEmail, 'ada@mevora.app');
    expect(authRepository.passwordSubmitted, isTrue);
  });

  testWidgets('register shows a localized email-already-in-use error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    authRepository.nextFailure = const AuthFailure(
      'An account already exists for that email.',
      kind: AuthErrorKind.emailInUse,
    );
    await tester.pumpWidget(
      _wrap(controller: controller, child: const RegisterPage()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, _l10n.email),
      'ada@mevora.app',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.password),
      'password1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _l10n.confirmPassword),
      'password1',
    );
    await tester.ensureVisible(find.text(_l10n.createAccount));
    await tester.tap(find.text(_l10n.createAccount));
    await tester.pump();
    await tester.pump();

    expect(find.text(_l10n.authEmailInUse), findsOneWidget);
  });

  testWidgets('password reset shows a generic success message', (tester) async {
    await tester.pumpWidget(
      _wrap(controller: controller, child: const PasswordResetPage()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, _l10n.email),
      'ada@mevora.app',
    );
    await tester.tap(find.text(_l10n.sendResetLink));
    await tester.pump();
    await tester.pump();

    expect(authRepository.lastResetEmail, 'ada@mevora.app');
    expect(find.text(_l10n.resetEmailSentTitle), findsOneWidget);
    expect(find.text(_l10n.resetEmailSentMessage), findsOneWidget);
  });

  testWidgets('login shows Mevora branding and provider buttons', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(controller: controller, child: const LoginPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('MEVORA'), findsOneWidget);
    expect(find.text(_l10n.loginSlogan), findsOneWidget);
    expect(find.text(_l10n.continueWithGoogle), findsOneWidget);
    expect(find.text(_l10n.continueWithApple), findsOneWidget);
    expect(find.text(_l10n.continueWithSpotify), findsOneWidget);
    expect(find.text(_l10n.continueWithPhone), findsOneWidget);
    expect(find.text(_l10n.continueWithEmail), findsOneWidget);
    expect(find.text(_l10n.termsOfService), findsOneWidget);
    expect(find.text(_l10n.privacyPolicy), findsOneWidget);
  });

  testWidgets('phone entry shows an error for an empty number', (tester) async {
    await tester.pumpWidget(
      _wrap(controller: controller, child: const PhoneLoginScreen()),
    );
    await tester.pump();

    await tester.tap(find.text(_l10n.sendCode));
    await tester.pump();

    expect(find.text(_l10n.authInvalidPhone), findsWidgets);
  });

  testWidgets('otp input auto-focuses and accepts a pasted 6-digit code', (
    tester,
  ) async {
    String? completed;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: OtpCodeInput(onChanged: (_) {}, onCompleted: (code) => completed = code),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    expect(completed, '123456');
  });
}
