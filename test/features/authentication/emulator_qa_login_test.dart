import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/emulator_qa_login.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/presentation/widgets/emulator_qa_login_panel.dart';

/// These tests run WITHOUT the QA dart-defines, which is the production shape:
/// no QA_EMAIL_A/B, no QA_PASSWORD compiled in. That is exactly the state a
/// release build ships in, so "disabled" is the default assertion here.
void main() {
  AppConfig configFor(AppEnvironment environment) =>
      AppConfig(environment: environment);

  Future<void> pumpPanel(
    WidgetTester tester,
    AppConfig config, {
    void Function(String email, String password)? onUse,
  }) async {
    await tester.pumpWidget(
      AppScope(
        config: config,
        logger: AppLogger(environment: config.environment),
        child: MaterialApp(
          home: Scaffold(
            body: EmulatorQaLoginPanel(
              onUseAccount: onUse ?? (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('6. no QA credentials exist in a production configuration', () {
    test('no accounts are compiled in without the dart-defines', () {
      expect(EmulatorQaLogin.accounts, isEmpty);
    });

    test('the gate is closed for every environment without credentials', () {
      for (final environment in AppEnvironment.values) {
        expect(
          EmulatorQaLogin.isEnabled(configFor(environment)),
          isFalse,
          reason: '$environment must not expose QA login without credentials',
        );
      }
    });
  });

  group('2/3. QA login is unreachable in production mode', () {
    test('production never enables emulators, so never enables QA login', () {
      final production = configFor(AppEnvironment.production);
      expect(production.useEmulators, isFalse);
      expect(production.useAuthEmulator, isFalse);
      expect(EmulatorQaLogin.isEnabled(production), isFalse);
    });

    test('staging never enables emulators either', () {
      final staging = configFor(AppEnvironment.staging);
      expect(staging.useEmulators, isFalse);
      expect(EmulatorQaLogin.isEnabled(staging), isFalse);
    });

    test('3. resolving a shortcut is refused when the gate is closed', () {
      final production = configFor(AppEnvironment.production);
      expect(
        EmulatorQaLogin.resolve(production, 'qa_user_a@mevora.test'),
        isNull,
      );
      expect(
        EmulatorQaLogin.resolve(production, 'anything@example.com'),
        isNull,
      );
    });

    testWidgets('1/2. the panel renders nothing when the gate is closed', (
      tester,
    ) async {
      await pumpPanel(tester, configFor(AppEnvironment.production));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.textContaining('Emulator QA'), findsNothing);
    });

    testWidgets('the panel is also absent in development without credentials', (
      tester,
    ) async {
      // Development alone is not enough — the credentials gate still applies.
      await pumpPanel(tester, configFor(AppEnvironment.development));
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('no shortcut can fire while the gate is closed', (
      tester,
    ) async {
      var fired = false;
      await pumpPanel(
        tester,
        configFor(AppEnvironment.production),
        onUse: (_, _) => fired = true,
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(fired, isFalse);
    });
  });

  group('5. production auth providers are untouched', () {
    test('the QA gate depends only on emulator config, nothing else', () {
      // If this ever needs another input, the change is deliberate and visible.
      final development = configFor(AppEnvironment.development);
      expect(
        EmulatorQaLogin.isEnabled(development),
        development.useAuthEmulator && EmulatorQaLogin.accounts.isNotEmpty,
      );
    });
  });
}
