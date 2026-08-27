import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/humor/domain/services/humor_education_store.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_lab_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HumorEducationStore> store() async {
    SharedPreferences.setMockInitialValues({});
    return HumorEducationStore(
      preferences: await SharedPreferences.getInstance(),
    );
  }

  HumorController controller() {
    return HumorController(
      repository: HumorRepositoryImpl(
        dataSource: MockHumorDataSource(seed: const []),
      ),
      adService: const NoopHumorAdService(),
      adsSettings: const HumorAdsSettings(enabled: false),
    );
  }

  testWidgets('first entry shows intro then feed after CTA', (tester) async {
    final education = await store();
    final c = controller();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: HumorLabPage(
          controller: c,
          educationStore: education,
          uidOverride: 'edu_user_1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mizahını keşfet'), findsOneWidget);
    expect(find.text('Mizahımı Keşfet'), findsOneWidget);
    expect(find.textContaining('Mizah profilin oluşuyor'), findsOneWidget);

    await tester.tap(find.text('Mizahımı Keşfet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(await education.isIntroSeen('edu_user_1'), isTrue);
    expect(find.text('Mizahımı Keşfet'), findsNothing);
  });

  testWidgets('second entry skips intro', (tester) async {
    final education = await store();
    await education.markIntroSeen('edu_user_2');
    final c = controller();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: HumorLabPage(
          controller: c,
          educationStore: education,
          uidOverride: 'edu_user_2',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Mizahımı Keşfet'), findsNothing);
    expect(find.text('Mizah Labı'), findsWidgets);
  });
}
