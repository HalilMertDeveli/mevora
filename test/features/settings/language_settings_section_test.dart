import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/settings/presentation/widgets/language_settings_section.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  testWidgets('settings radio switches locale live without restart', (tester) async {
    final controller = LanguageController(
      repository: LanguageRepository(local: MemoryLanguageDataSource()),
      deviceLocale: const Locale('en'),
    );
    await controller.load();

    await tester.pumpWidget(
      LanguageScope(
        controller: controller,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return MaterialApp(
              theme: AppTheme.light(),
              locale: controller.locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: const Scaffold(body: LanguageSettingsSection()),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(controller.language, AppLanguage.english);
    expect(find.text('English 🇬🇧'), findsOneWidget);
    expect(find.text('Türkçe 🇹🇷'), findsOneWidget);

    await tester.tap(find.text('Türkçe 🇹🇷'));
    await tester.pump();
    await tester.pump();

    expect(controller.language, AppLanguage.turkish);
    expect(controller.locale, const Locale('tr'));
    expect(find.text('Dil'), findsOneWidget);
  });
}
