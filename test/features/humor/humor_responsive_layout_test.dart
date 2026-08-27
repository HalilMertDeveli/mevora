import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/humor/domain/services/humor_education_store.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_lab_page.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_intro_view.dart';
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

  Future<void> pumpIntro(
    WidgetTester tester, {
    required Size size,
    required HumorEducationStore education,
    HumorController? c,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: HumorLabPage(
          controller: c ?? controller(),
          educationStore: education,
          uidOverride: 'responsive_user',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('intro shows full-width hierarchy without narrow premium row', (
    tester,
  ) async {
    final education = await store();
    await pumpIntro(
      tester,
      size: const Size(390, 844),
      education: education,
    );

    expect(find.text('Mizahını keşfet'), findsOneWidget);
    expect(find.text('Mizahımı Keşfet'), findsOneWidget);
    expect(find.textContaining('Mizah profilin oluşuyor'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Reklamsız Mizah Labı'), findsOneWidget);
    expect(find.text('Premium\'u İncele'), findsOneWidget);

    // Legacy broken feed chrome must not appear on intro.
    expect(find.text('Premium ile reklamsız Mizah Labı'), findsNothing);

    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(360, 640),
    Size(390, 844),
    Size(412, 915),
    Size(430, 932),
  ]) {
    testWidgets('intro lays out at ${size.width}x${size.height}', (
      tester,
    ) async {
      final education = await store();
      await pumpIntro(tester, size: size, education: education);

    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.byType(HumorIntroView), findsOneWidget);
    expect(find.text('Mizahımı Keşfet'), findsOneWidget);
    });
  }

  testWidgets('standalone intro max-width centers on large screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: HumorIntroView(
          onContinue: () {},
          interactionCount: 17,
          isPremium: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('17 içerik değerlendirdin.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
