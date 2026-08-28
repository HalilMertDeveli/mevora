import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/humor/domain/services/humor_education_store.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_lab_page.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_intro_view.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Faz 2 — full HumorLabPage responsive layout (player stubbed; not playback E2E).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uid = 'responsive_feed_user';
  const adsOff = HumorAdsSettings(enabled: false);

  const targetSizes = <Size>[
    Size(360, 640),
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(430, 932),
  ];

  setUp(() {
    HumorContentPlayer.debugDisableHeavyMedia = true;
    HumorContentPlayer.debugTrackStubControllers = false;
  });

  tearDown(() {
    HumorContentPlayer.debugDisableHeavyMedia = false;
    HumorContentPlayer.debugTrackStubControllers = false;
  });

  Future<HumorEducationStore> educationStore({bool introSeen = true}) async {
    SharedPreferences.setMockInitialValues({
      if (introSeen) 'mevora.humor.introSeen.$uid': true,
      'mevora.humor.ratingHelpDismissed.$uid': true,
      'mevora.humor.adInfoSeen.$uid': true,
    });
    return HumorEducationStore(
      preferences: await SharedPreferences.getInstance(),
    );
  }

  List<HumorContent> youtubeFeed(int count) {
    return List<HumorContent>.generate(count, (i) {
      const id = 'dQw4w9WgXcQ';
      return HumorContent(
        contentId: 'ext_youtube_responsive_$i',
        type: HumorContentType.video,
        language: 'tr',
        category: HumorCategory.silly,
        provider: 'youtube',
        sourceId: id,
        textBody: 'Responsive feed item $i',
        embedUrl: 'https://www.youtube.com/embed/$id?playsinline=1',
        downloadUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        thumbUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        aspectRatio: 9 / 16,
        attributionRequired: true,
      );
    });
  }

  HumorController feedController({MockHumorDataSource? source}) {
    return HumorController(
      repository: HumorRepositoryImpl(
        dataSource: source ?? MockHumorDataSource(seed: youtubeFeed(12)),
      ),
      adService: const NoopHumorAdService(),
      adsSettings: adsOff,
      isPremium: true,
    );
  }

  Future<void> pumpHumorLab(
    WidgetTester tester, {
    required Size size,
    required HumorEducationStore education,
    required HumorController controller,
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
          controller: controller,
          educationStore: education,
          uidOverride: uid,
        ),
      ),
    );
  }

  Future<void> waitForFeed(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Komik').evaluate().isNotEmpty) {
        break;
      }
      if (find.byType(MevoraErrorView).evaluate().isNotEmpty) {
        break;
      }
      if (find
          .text('Şimdilik gösterecek yeni bir içerik yok.')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> expectLoadedFeedChrome(WidgetTester tester) async {
    expect(find.byType(HumorRatingBar), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets);
    expect(find.text('Bunu komik buldun mu?'), findsOneWidget);
  }

  testWidgets('intro responsive hierarchy', (tester) async {
    final education = await educationStore(introSeen: false);
    final controller = feedController();
    await pumpHumorLab(
      tester,
      size: const Size(390, 844),
      education: education,
      controller: controller,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mizahını keşfet'), findsOneWidget);
    expect(find.byType(HumorIntroView), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  group('full feed loaded', () {
    for (final size in targetSizes) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final education = await educationStore();
        final controller = feedController();
        await pumpHumorLab(
          tester,
          size: size,
          education: education,
          controller: controller,
        );
        await waitForFeed(tester);
        await expectLoadedFeedChrome(tester);
        expect(find.byType(HumorContentPlayer), findsWidgets);
        controller.dispose();
      });
    }
  });

  group('feed UI states', () {
    for (final size in targetSizes) {
      testWidgets('loading ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final education = await educationStore();
        final source = MockHumorDataSource(seed: youtubeFeed(6));
        final controller = feedController(source: source);
        await pumpHumorLab(
          tester,
          size: size,
          education: education,
          controller: controller,
        );
        await tester.pump();
        expect(find.text('Videolar yükleniyor…'), findsOneWidget);
        await waitForFeed(tester);
        controller.dispose();
      });

      testWidgets('error ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final education = await educationStore();
        final controller = feedController(
          source: MockHumorDataSource(failFeed: true),
        );
        await pumpHumorLab(
          tester,
          size: size,
          education: education,
          controller: controller,
        );
        await waitForFeed(tester);
        expect(find.byType(MevoraErrorView), findsOneWidget);
        expect(find.text('Tekrar dene'), findsOneWidget);
        controller.dispose();
      });

      testWidgets('empty ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final education = await educationStore();
        final controller = feedController(
          source: MockHumorDataSource(seed: const []),
        );
        await pumpHumorLab(
          tester,
          size: size,
          education: education,
          controller: controller,
        );
        await waitForFeed(tester);
        expect(
          find.text('Şimdilik gösterecek yeni bir içerik yok.'),
          findsOneWidget,
        );
        controller.dispose();
      });
    }

    testWidgets('loading more overlay', (tester) async {
      final education = await educationStore();
      final controller = feedController();
      await pumpHumorLab(
        tester,
        size: const Size(360, 640),
        education: education,
        controller: controller,
      );
      await waitForFeed(tester);
      unawaited(controller.onPageChanged(9));
      await tester.pump();
      expect(find.text('Sonraki video hazırlanıyor…'), findsOneWidget);
      for (var i = 0; i < 20; i++) {
        if (!controller.state.isLoadingMore) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      controller.dispose();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('vertical PageView + rating', () {
    testWidgets('page transition advances active item', (tester) async {
      final education = await educationStore();
      final controller = feedController(
        source: MockHumorDataSource(seed: youtubeFeed(5)),
      );
      await pumpHumorLab(
        tester,
        size: const Size(390, 844),
        education: education,
        controller: controller,
      );
      await waitForFeed(tester);
      expect(controller.state.currentIndex, 0);
      await controller.onPageChanged(1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.state.currentIndex, 1);
      controller.dispose();
    });

    testWidgets('rating buttons are tappable', (tester) async {
      final education = await educationStore();
      final controller = feedController(
        source: MockHumorDataSource(seed: youtubeFeed(4)),
      );
      await pumpHumorLab(
        tester,
        size: const Size(360, 640),
        education: education,
        controller: controller,
      );
      await waitForFeed(tester);
      final funny = find.descendant(
        of: find.byType(HumorRatingBar),
        matching: find.text('Komik'),
      );
      await tester.ensureVisible(funny);
      await tester.tap(funny);
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.state.lastRated, HumorRating.funny);
      controller.dispose();
    });
  });
}
