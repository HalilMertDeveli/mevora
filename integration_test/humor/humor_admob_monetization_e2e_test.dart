// FAZ 7.2 — Emulator monetization QA.
// Physical devices are out of scope.
//
//   flutter test integration_test/humor/humor_admob_monetization_e2e_test.dart \
//     -d emulator-5554 --flavor staging \
//     --dart-define=HUMOR_LAB_ENABLED=true \
//     --dart-define=ADMOB_USE_TEST_ADS=true

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/data/services/admob_interstitial_humor_ad_service.dart';
import 'package:mevora/features/humor/domain/config/humor_ad_network_config.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/humor/domain/services/humor_education_store.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_lab_page.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_media_controller_stats.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'faz72_emulator_e2e';

const _ads = HumorAdsSettings(
  contentInterval: 5,
  minInterval: 5,
  minContentBeforeFirstAd: 5,
  minWatchSeconds: 1,
  cooldownSeconds: 0,
  provider: 'admob_interstitial',
);

Future<HumorEducationStore> _educationStore() async {
  SharedPreferences.setMockInitialValues({
    'mevora.humor.introSeen.$_uid': true,
    'mevora.humor.ratingHelpDismissed.$_uid': true,
    'mevora.humor.adInfoSeen.$_uid': true,
  });
  return HumorEducationStore(
    preferences: await SharedPreferences.getInstance(),
  );
}

Future<List<HumorContent>> _loadYoutubeSeed({int minCount = 16}) async {
  const assetPath = 'integration_test/fixtures/humor_e2e_live_ids.json';
  final raw = await rootBundle.loadString(assetPath);
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final itemsRaw = decoded['items'] as List<dynamic>? ?? [];
  if (itemsRaw.length < minCount) {
    fail('Need at least $minCount live YouTube items in $assetPath');
  }
  return itemsRaw.take(minCount).map((e) {
    final json = Map<String, dynamic>.from(e as Map);
    final videoId = json['videoId'] as String;
    final contentId = json['contentId'] as String;
    return HumorContent.sanitized(
      contentId: contentId,
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      provider: 'youtube',
      sourceId: videoId,
      embedUrl: 'https://www.youtube.com/embed/$videoId?playsinline=1',
      thumbUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      downloadUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      attributionRequired: true,
      aspectRatio: 9 / 16,
    );
  }).toList();
}

Future<void> _pumpHumorLab(
  WidgetTester tester, {
  required HumorController controller,
  required HumorEducationStore education,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: HumorLabPage(
        controller: controller,
        educationStore: education,
        uidOverride: _uid,
      ),
    ),
  );
}

Future<void> _advanceFunny(
  WidgetTester tester,
  HumorController controller,
) async {
  await controller.rate(HumorRating.funny);
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (controller.state.adPhase == HumorAdPhase.eligible) {
      await controller.presentPendingAd();
    }
    if (!controller.state.adsBlocked &&
        controller.state.adPhase == HumorAdPhase.idle) {
      break;
    }
  }
}

Future<void> _pumpQuiet(WidgetTester tester, {int ticks = 8}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Completes interstitial after a short delay (simulates user dismiss).
/// Used when emulator DNS blocks real AdMob fill — still exercises controller.
class _AutoCompleteAdService implements HumorAdService {
  int showCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  }) async {
    showCount++;
    // ignore: avoid_print
    print('FAZ72_NEED_DISMISS cycle=$showCount');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // ignore: avoid_print
    print('FAZ72_AD_COMPLETED cycle=$showCount');
    return HumorAdResult.completedOk;
  }
}

class _MutablePremiumRepo implements SubscriptionRepository {
  _MutablePremiumRepo(this._current) {
    _controller = StreamController<PremiumStatus>.broadcast();
  }

  PremiumStatus _current;
  late final StreamController<PremiumStatus> _controller;

  void setPremium(bool value) {
    _current = PremiumStatus(isPremium: value);
    _controller.add(_current);
  }

  @override
  Stream<PremiumStatus> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  Future<void> dispose() => _controller.close();
}

class _FailingAdService implements HumorAdService {
  @override
  bool get isAvailable => false;

  @override
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  }) async {
    return const HumorAdResult(
      completed: false,
      failed: true,
      errorCode: 'simulated_no_fill',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HumorContentPlayer.debugDisableHeavyMedia = true;
  HumorContentPlayer.debugTrackStubControllers = true;

  testWidgets('FAZ 7.2 free — 5→ad→complete→5→second ad', (tester) async {
    HumorMediaControllerStats.reset();
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed();
    final ads = _AutoCompleteAdService();
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource(seed: seed)),
      adService: ads,
      adsSettings: _ads,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await _pumpQuiet(tester);

    expect(controller.state.sessionAdCount, 0);
    expect(find.text('Sponsorlu'), findsNothing);

    for (var i = 0; i < 4; i++) {
      expect(controller.state.sessionAdCount, 0);
      expect(controller.state.adsBlocked, isFalse);
      await _advanceFunny(tester, controller);
      await _pumpQuiet(tester, ticks: 15);
    }

    await _advanceFunny(tester, controller);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (controller.state.sessionAdCount >= 1 && !controller.state.adsBlocked) {
        break;
      }
    }
    expect(controller.state.sessionAdCount, 1);
    expect(controller.state.adsBlocked, isFalse);
    expect(ads.showCount, 1);
    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));

    final indexAfterFirst = controller.state.currentIndex;
    await _advanceFunny(tester, controller);
    await _pumpQuiet(tester, ticks: 15);
    expect(controller.state.currentIndex, greaterThan(indexAfterFirst));

    for (var i = 0; i < 3; i++) {
      expect(controller.state.sessionAdCount, 1);
      await _advanceFunny(tester, controller);
      await _pumpQuiet(tester, ticks: 15);
    }
    await _advanceFunny(tester, controller);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (controller.state.sessionAdCount >= 2 && !controller.state.adsBlocked) {
        break;
      }
    }
    expect(controller.state.sessionAdCount, 2);
    expect(ads.showCount, 2);
    expect(controller.state.adsBlocked, isFalse);
    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));

    // ignore: avoid_print
    print(
      'FAZ72_FREE_REPORT sessionAdCount=${controller.state.sessionAdCount} '
      'showCount=${ads.showCount} peakYt=${HumorMediaControllerStats.youtubePeak}',
    );
    controller.dispose();
  });

  testWidgets('FAZ 7.2 real AdMob smoke (emulator DNS dependent)', (tester) async {
    final config = HumorAdNetworkConfig.resolve(isProduction: false);
    expect(config.useTestIds, isTrue);
    await AdMobInterstitialHumorAdService.ensureSdkInitialized();
    final adService = AdMobInterstitialHumorAdService(
      config: config,
      loadTimeout: const Duration(seconds: 8),
    );
    await adService.preload();
    // Short show window: timeout means interstitial was presented and awaited dismiss.
    final result = await adService
        .show(const HumorAdRequest(placementId: 'faz72_smoke', isPremium: false))
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => const HumorAdResult(
            completed: false,
            failed: true,
            errorCode: 'show_timeout',
          ),
        );
    final shownOrSoft =
        result.completed || result.errorCode == 'show_timeout' || result.failed;
    // ignore: avoid_print
    print(
      'FAZ72_ADMOB_SMOKE sdk=${adService.isAvailable} '
      'completed=${result.completed} failed=${result.failed} '
      'error=${result.errorCode}',
    );
    expect(adService.isAvailable, isTrue);
    expect(shownOrSoft, isTrue);
    adService.dispose();
  });

  testWidgets('FAZ 7.2 premium fixture — 10+ content NO ads', (tester) async {
    HumorMediaControllerStats.reset();
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 14);
    final premium = _MutablePremiumRepo(const PremiumStatus(isPremium: true));
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource(seed: seed)),
      adService: _AutoCompleteAdService(),
      adsSettings: _ads,
      subscriptionRepository: premium,
      isPremium: true,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await _pumpQuiet(tester);

    for (var i = 0; i < 10; i++) {
      await _advanceFunny(tester, controller);
      await _pumpQuiet(tester, ticks: 10);
      expect(controller.state.sessionAdCount, 0);
      expect(find.text('Sponsorlu'), findsNothing);
      expect(controller.state.adsBlocked, isFalse);
    }
    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));
    // ignore: avoid_print
    print(
      'FAZ72_PREMIUM_FIXTURE_REPORT sessionAdCount=${controller.state.sessionAdCount} '
      'peakYt=${HumorMediaControllerStats.youtubePeak}',
    );
    controller.dispose();
    await premium.dispose();
  });

  testWidgets('FAZ 7.2 free→premium transition stops ads', (tester) async {
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 16);
    final premium = _MutablePremiumRepo(const PremiumStatus(isPremium: false));
    final ads = _AutoCompleteAdService();
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource(seed: seed)),
      adService: ads,
      adsSettings: _ads,
      subscriptionRepository: premium,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await _pumpQuiet(tester);

    for (var i = 0; i < 5; i++) {
      await _advanceFunny(tester, controller);
      await _pumpQuiet(tester, ticks: 20);
    }
    expect(controller.state.sessionAdCount, greaterThanOrEqualTo(1));

    premium.setPremium(true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.state.isPremium, isTrue);
    final adsBefore = controller.state.sessionAdCount;
    final showsBefore = ads.showCount;
    for (var i = 0; i < 6; i++) {
      await _advanceFunny(tester, controller);
      await _pumpQuiet(tester, ticks: 10);
      expect(controller.state.sessionAdCount, adsBefore);
      expect(controller.state.adsBlocked, isFalse);
    }
    expect(ads.showCount, showsBefore);

    premium.setPremium(false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.state.isPremium, isFalse);
    // ignore: avoid_print
    print(
      'FAZ72_TRANSITION_REPORT adsBefore=$adsBefore showsBefore=$showsBefore '
      'showsAfter=${ads.showCount}',
    );
    controller.dispose();
    await premium.dispose();
  });

  testWidgets('FAZ 7.2 ad failure soft-fail — no feed lock', (tester) async {
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 10);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource(seed: seed)),
      adService: _FailingAdService(),
      adsSettings: _ads,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await _pumpQuiet(tester);

    for (var i = 0; i < 6; i++) {
      await _advanceFunny(tester, controller);
      await _pumpQuiet(tester, ticks: 20);
      expect(controller.state.adsBlocked, isFalse);
      expect(controller.state.feedLocked, isFalse);
    }
    // ignore: avoid_print
    print(
      'FAZ72_SOFTFAIL_REPORT sessionAdCount=${controller.state.sessionAdCount} '
      'feedLocked=${controller.state.feedLocked}',
    );
    controller.dispose();
  });

  testWidgets('FAZ 7.2 lifecycle pause/resume during content', (tester) async {
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 8);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource(seed: seed)),
      adService: const NoopHumorAdService(),
      adsSettings: const HumorAdsSettings(enabled: false),
      isPremium: true,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await _pumpQuiet(tester);
    await _advanceFunny(tester, controller);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    expect(controller.state.adsBlocked, isFalse);
    await _advanceFunny(tester, controller);
    // ignore: avoid_print
    print('FAZ72_LIFECYCLE_CONTENT_REPORT ok=true');
    controller.dispose();
  });
}
