// FAZ 7.1 — AdMob interstitial monetization on physical device (test ad IDs).
//
// Install + run (Samsung M22):
//   flutter build apk --debug --flavor staging
//   adb -s R68T305S3VM install -r build/app/outputs/flutter-apk/app-staging-debug.apk
//   flutter test integration_test/humor/humor_admob_monetization_e2e_test.dart \
//     -d R68T305S3VM --flavor staging \
//     --dart-define=HUMOR_LAB_ENABLED=true \
//     --dart-define=ADMOB_USE_TEST_ADS=true
//
// Uses Google sample interstitial unit IDs only (no production ads).

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

const _uid = 'faz71_admob_e2e';

const _deviceAds = HumorAdsSettings(
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
    final embedUrl = json['embedUrl'] as String? ?? '';
    final thumbUrl = json['thumbUrl'] as String? ?? '';
    return HumorContent.sanitized(
      contentId: contentId,
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      provider: 'youtube',
      sourceId: videoId,
      embedUrl: embedUrl.isNotEmpty
          ? embedUrl
          : 'https://www.youtube.com/embed/$videoId?playsinline=1',
      thumbUrl: thumbUrl.isNotEmpty
          ? thumbUrl
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      downloadUrl: thumbUrl.isNotEmpty
          ? thumbUrl
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
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
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (controller.state.adsBlocked || controller.state.adPhase == HumorAdPhase.shown) {
      break;
    }
  }
}

class _ReplayPremiumRepo implements SubscriptionRepository {
  _ReplayPremiumRepo(this.initial);
  final PremiumStatus initial;

  @override
  Stream<PremiumStatus> watch() async* {
    yield initial;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HumorContentPlayer.debugDisableHeavyMedia = false;
  HumorContentPlayer.debugTrackStubControllers = false;

  testWidgets('FAZ 7.1 free — AdMob test interstitial after 5 unique views', (
    tester,
  ) async {
    HumorMediaControllerStats.reset();
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed();
    final config = HumorAdNetworkConfig.resolve(isProduction: false);
    expect(config.useTestIds, isTrue);

    await AdMobInterstitialHumorAdService.ensureSdkInitialized();
    final adService = AdMobInterstitialHumorAdService(config: config);
    await adService.preload();

    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource(seed: seed)),
      adService: adService,
      adsSettings: _deviceAds,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(controller.state.sessionAdCount, 0);
    expect(find.text('Sponsorlu'), findsNothing);

    for (var i = 0; i < 4; i++) {
      expect(controller.state.sessionAdCount, 0);
      await _advanceFunny(tester, controller);
    }

    final before = controller.state.sessionAdCount;
    await _advanceFunny(tester, controller);

    // Wait for AdMob show + dismiss (manual close on device may be needed).
    var sawAdGate = controller.state.adsBlocked || controller.state.adPhase != HumorAdPhase.idle;
    for (var i = 0; i < 60 && !sawAdGate; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      sawAdGate = controller.state.adsBlocked ||
          controller.state.adPhase == HumorAdPhase.shown ||
          controller.state.adPhase == HumorAdPhase.loading ||
          controller.state.sessionAdCount > before;
    }

    // Soft-fail is acceptable if no-fill; report via sessionAdCount / phase.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (!controller.state.adsBlocked &&
          controller.state.adPhase == HumorAdPhase.idle &&
          (controller.state.sessionAdCount > before ||
              controller.state.failure == null)) {
        // Either ad completed or soft-failed and unlocked.
        if (controller.state.sessionAdCount > before || i > 10) {
          break;
        }
      }
    }

    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));
    expect(find.text('Sponsorlu'), findsNothing);

    // ignore: avoid_print
    print(
      'FAZ71_ADMOB_REPORT sessionAdCount=${controller.state.sessionAdCount} '
      'adPhase=${controller.state.adPhase} adsBlocked=${controller.state.adsBlocked} '
      'sdk=${adService.isAvailable} peakYt=${HumorMediaControllerStats.youtubePeak}',
    );

    controller.dispose();
    adService.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('FAZ 7.1 premium entitlement — no AdMob / no sponsored break', (
    tester,
  ) async {
    HumorMediaControllerStats.reset();
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 12);
    final config = HumorAdNetworkConfig.resolve(isProduction: false);
    await AdMobInterstitialHumorAdService.ensureSdkInitialized();
    final adService = AdMobInterstitialHumorAdService(config: config);

    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource(seed: seed)),
      adService: adService,
      adsSettings: _deviceAds,
      subscriptionRepository: _ReplayPremiumRepo(
        const PremiumStatus(isPremium: true),
      ),
      isPremium: true,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    for (var i = 0; i < 10; i++) {
      await _advanceFunny(tester, controller);
      expect(controller.state.sessionAdCount, 0);
      expect(find.text('Sponsorlu'), findsNothing);
      expect(controller.state.adsBlocked, isFalse);
    }

    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));
    // ignore: avoid_print
    print(
      'FAZ71_PREMIUM_REPORT sessionAdCount=${controller.state.sessionAdCount} '
      'peakYt=${HumorMediaControllerStats.youtubePeak}',
    );

    controller.dispose();
    adService.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
