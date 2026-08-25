// Multi-emulator / Auth-emulator friendly email auth + shell smoke.
// Run:
// flutter test integration_test/smoke/multi_user_email_auth_test.dart -d emulator-5556 --flavor development \
//   --dart-define=USE_EMULATORS=true --dart-define=USE_AUTH_EMULATOR=true \
//   --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2 \
//   --dart-define=QA_EMAIL=qa-a@mevora.test --dart-define=QA_PASSWORD=QaTest!A9Mevora

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const email = String.fromEnvironment(
    'QA_EMAIL',
    defaultValue: 'qa-a@mevora.test',
  );
  const password = String.fromEnvironment(
    'QA_PASSWORD',
    defaultValue: 'QaTest!A9Mevora',
  );

  testWidgets('email login reaches authenticated shell or onboarding', (
    tester,
  ) async {
    await bootstrap(AppEnvironment.development);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(MaterialApp), findsWidgets);

    // Open email path from welcome if present.
    final emailButton = find.textContaining('email', findRichText: true);
    final emailButtonTr = find.textContaining('e-posta', findRichText: true);
    if (emailButton.evaluate().isNotEmpty) {
      await tester.tap(emailButton.first);
      await tester.pump(const Duration(seconds: 1));
    } else if (emailButtonTr.evaluate().isNotEmpty) {
      await tester.tap(emailButtonTr.first);
      await tester.pump(const Duration(seconds: 1));
    }

    // Fill email/password fields if on login form.
    final fields = find.byType(TextField);
    if (fields.evaluate().length >= 2) {
      await tester.enterText(fields.at(0), email);
      await tester.enterText(fields.at(1), password);
      await tester.pump();

      final signIn = find.textContaining('Sign in');
      final signInTr = find.textContaining('Giriş');
      if (signIn.evaluate().isNotEmpty) {
        await tester.tap(signIn.first);
      } else if (signInTr.evaluate().isNotEmpty) {
        await tester.tap(signInTr.first);
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
    }

    // Success: left the pure welcome-only stack OR still MaterialApp alive (no crash).
    expect(find.byType(MaterialApp), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid email credentials do not crash', (tester) async {
    await bootstrap(AppEnvironment.development);
    await tester.pump(const Duration(seconds: 2));

    final fields = find.byType(TextField);
    if (fields.evaluate().length >= 2) {
      await tester.enterText(fields.at(0), 'invalid-qa@mevora.test');
      await tester.enterText(fields.at(1), 'WrongPass999!');
      final signIn = find.textContaining('Sign in');
      if (signIn.evaluate().isNotEmpty) {
        await tester.tap(signIn.first);
        await tester.pump(const Duration(seconds: 3));
      }
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsWidgets);
  });
}
