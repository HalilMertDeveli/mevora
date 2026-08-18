import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/app.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'helpers/fake_auth.dart';

void main() {
  testWidgets('app boots and reaches the login gate', (tester) async {
    const environment = AppEnvironment.development;
    const logger = AppLogger(environment: environment);
    final authController = AuthController(
      authRepository: FakeAuthRepository(),
      userDocumentRepository: FakeUserDocumentRepository(),
      logger: logger,
    );
    final language = LanguageController(
      repository: LanguageRepository(
        local: MemoryLanguageDataSource(languageCode: 'en'),
      ),
      deviceLocale: const Locale('de'),
    );
    await language.load();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      MevoraApp(
        config: const AppConfig(environment: environment),
        logger: logger,
        authController: authController,
        languageController: language,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text(l10n.continueWithGoogle), findsOneWidget);
  });
}
