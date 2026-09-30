import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/app.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_onboarding_services.dart';
import 'app_operations_fakes.dart';

/// The whole app, wired the way bootstrap wires it, with a controllable
/// operations document.
void main() {
  const environment = AppEnvironment.development;
  const logger = AppLogger(environment: environment);
  final l10n = lookupAppLocalizations(const Locale('en'));

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  Future<FakeAppOperationsRepository> pumpApp(
    WidgetTester tester, {
    AppOperationsConfig? cached,
  }) async {
    final authController = AuthController(
      authRepository: FakeAuthRepository(),
      userDocumentRepository: FakeUserDocumentRepository(),
      logger: logger,
    );
    final language = LanguageController(
      repository: LanguageRepository(
        local: MemoryLanguageDataSource(languageCode: 'en'),
      ),
    );
    await language.load();
    final repository = FakeAppOperationsRepository();
    final operations = fakeOperationsController(
      repository: repository,
      cached: cached,
    );
    addTearDown(operations.dispose);
    await tester.pumpWidget(
      MevoraApp(
        config: const AppConfig(environment: environment),
        logger: logger,
        authController: authController,
        languageController: language,
        onboardingServices: createFakeOnboardingServices(),
        appOperations: operations,
      ),
    );
    await settle(tester);
    return repository;
  }

  testWidgets('a cached maintenance flag gates a cold start offline', (
    tester,
  ) async {
    await pumpApp(
      tester,
      cached: const AppOperationsConfig(maintenanceEnabled: true),
    );
    expect(find.text(l10n.appOpsMaintenanceMessage), findsOneWidget);
    expect(find.text(l10n.continueWithGoogle), findsNothing);
  });

  testWidgets('maintenance on and off, live, for a signed-out visitor', (
    tester,
  ) async {
    final repository = await pumpApp(tester);
    expect(find.text(l10n.continueWithGoogle), findsOneWidget);

    repository.emit(
      const AppOperationsConfig(
        maintenanceEnabled: true,
        maintenanceMessage: 'Back at ten',
      ),
    );
    await settle(tester);
    expect(find.text('Back at ten'), findsOneWidget);

    repository.emit(AppOperationsConfig.defaults);
    await settle(tester);
    expect(find.text('Back at ten'), findsNothing);
    expect(find.text(l10n.continueWithGoogle), findsOneWidget);
  });

  testWidgets('a required update blocks the app', (tester) async {
    final repository = await pumpApp(tester);
    repository.emit(
      const AppOperationsConfig(
        minimumVersion: PlatformValues(android: '9.0.0'),
      ),
    );
    await settle(tester);
    expect(find.text(l10n.appOpsUpdateRequiredTitle), findsOneWidget);
  });

  testWidgets('an announcement shows above the login screen', (tester) async {
    final repository = await pumpApp(tester);
    repository.emit(
      const AppOperationsConfig(
        announcement: AppAnnouncement(id: 'n1', message: 'New in Mevora'),
      ),
    );
    await settle(tester);
    expect(find.text('New in Mevora'), findsOneWidget);
    expect(find.text(l10n.continueWithGoogle), findsOneWidget);
  });
}
