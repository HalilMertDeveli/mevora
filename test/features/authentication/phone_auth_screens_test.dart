import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/screens/otp_verification_screen.dart';
import 'package:mevora/features/authentication/presentation/screens/phone_login_screen.dart';
import 'package:mevora/features/authentication/presentation/widgets/country_code_selector.dart';
import 'package:mevora/features/authentication/presentation/widgets/otp_code_input.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';

final _l10n = lookupAppLocalizations(const Locale('tr'));

Widget _harness(AuthController auth, Widget child) {
  final router = GoRouter(
    initialLocation: '/under-test',
    routes: [
      GoRoute(path: '/under-test', builder: (context, state) => child),
      GoRoute(
        path: AppRoutes.phone,
        builder: (context, state) => const PhoneLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.phoneOtp,
        builder: (context, state) => const OtpVerificationScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const SizedBox(),
      ),
    ],
  );
  return AppScope(
    config: const AppConfig(environment: AppEnvironment.development),
    logger: const AppLogger(environment: AppEnvironment.development),
    child: AuthScope(
      controller: auth,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
}

void main() {
  const challenge = PhoneChallenge(
    verificationId: 'vid',
    e164Phone: '+905551112233',
    maskedPhone: '+90 5•• ••• •• 33',
  );

  testWidgets('phone screen shows Turkish copy, country selector, and send', (
    tester,
  ) async {
    final auth = AuthController(
      authRepository: FakeAuthRepository(
        sendResult: const Success(challenge),
        sendDelay: const Duration(milliseconds: 300),
      ),
      userDocumentRepository: FakeUserDocumentRepository(),
      logger: const AppLogger(environment: AppEnvironment.development),
    );

    await tester.pumpWidget(_harness(auth, const PhoneLoginScreen()));
    await tester.pump();

    expect(find.text(_l10n.phoneTitle), findsOneWidget);
    expect(find.text(_l10n.phoneSubtitle), findsOneWidget);
    expect(find.text(_l10n.sendCode), findsOneWidget);
    expect(find.byType(CountryCodeSelector), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '5551112233');
    await tester.tap(find.text(_l10n.sendCode));
    await tester.pump();
    expect(find.text(_l10n.sendingSms), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text(_l10n.otpTitle), findsOneWidget);
    auth.dispose();
  });

  testWidgets('otp screen shows masked number, boxes, resend countdown', (
    tester,
  ) async {
    final auth = AuthController(
      authRepository: FakeAuthRepository(sendResult: const Success(challenge)),
      userDocumentRepository: FakeUserDocumentRepository(),
      logger: const AppLogger(environment: AppEnvironment.development),
    );
    auth.phoneAuth.updateNationalNumber('5551112233');
    await auth.phoneAuth.sendCode();

    await tester.pumpWidget(_harness(auth, const OtpVerificationScreen()));
    await tester.pump();

    expect(find.text(_l10n.otpTitle), findsOneWidget);
    expect(find.textContaining('5••'), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsOneWidget);
    expect(find.textContaining('saniye sonra'), findsOneWidget);
    auth.dispose();
  });

  testWidgets('invalid phone shows a Turkish error, never firebase codes', (
    tester,
  ) async {
    final auth = AuthController(
      authRepository: FakeAuthRepository(),
      userDocumentRepository: FakeUserDocumentRepository(),
      logger: const AppLogger(environment: AppEnvironment.development),
    );

    await tester.pumpWidget(_harness(auth, const PhoneLoginScreen()));
    await tester.tap(find.text(_l10n.sendCode));
    await tester.pump();

    expect(find.text(_l10n.authInvalidPhone), findsWidgets);
    expect(find.textContaining('firebase_auth'), findsNothing);
    auth.dispose();
  });
}
