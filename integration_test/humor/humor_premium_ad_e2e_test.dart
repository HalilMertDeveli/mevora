// Faz 6 — Premium + Sponsored Break real device E2E.
//
// Run on Samsung M22 (install APK first if flutter install hangs):
//   adb -s R68T305S3VM install -r build/app/outputs/flutter-apk/app-staging-debug.apk
//   flutter test integration_test/humor/humor_premium_ad_e2e_test.dart \
//     -d R68T305S3VM --flavor staging --dart-define=HUMOR_LAB_ENABLED=true
//
// Note: YouTube WebView intercepts widget taps on device; content advance uses
// HumorController.rate() while real YouTube + Sponsored Break UI still run.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/data/services/sponsored_break_humor_ad_service.dart';
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

const _uid = 'faz6_device_e2e';

/// Production-like policy with 1s min watch for faster device runs.
const _deviceAds = HumorAdsSettings(
  contentInterval: 5,
  minInterval: 5,
  minContentBeforeFirstAd: 5,
  minWatchSeconds: 1,
  cooldownSeconds: 0,
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

Future<List<HumorContent>> _loadYoutubeSeed({int minCount = 15}) async {
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

/// Real YouTube WebView blocks widget taps on device; controller API matches UI path.
Future<void> _advanceFunny(
  WidgetTester tester,
  HumorController controller,
) async {
  await controller.rate(HumorRating.funny);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _waitForSponsoredBreak(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('Sponsorlu').evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Sponsored break did not appear within 10s');
}

Future<void> _dismissSponsoredBreak(WidgetTester tester) async {
  expect(find.text('Sponsorlu'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  final continueBtn = find.text('Devam et');
  expect(continueBtn, findsOneWidget);
  await tester.tap(continueBtn);
  await tester.pumpAndSettle();
  expect(find.text('Sponsorlu'), findsNothing);
}

/// Replays [initial] to new subscribers (broadcast streams miss pre-subscribe events).
class _ReplayPremiumRepo implements SubscriptionRepository {
  _ReplayPremiumRepo(this.initial, [this._updates]);
  final PremiumStatus initial;
  final StreamController<PremiumStatus>? _updates;

  @override
  Stream<PremiumStatus> watch() async* {
    yield initial;
    if (_updates != null) {
      yield* _updates!.stream;
    }
  }
}

class _FailingAdService implements HumorAdService {
  @override
  bool get isAvailable => false;

  @override
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  }) async {
    return HumorAdResult.failedSoft;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  HumorContentPlayer.debugDisableHeavyMedia = false;
  HumorContentPlayer.debugTrackStubControllers = false;

  testWidgets('Faz 6: free user — no ad on entry, ad after 5 views, second at 10', (
    tester,
  ) async {
    HumorMediaControllerStats.reset();
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed();
    final source = MockHumorDataSource(seed: seed);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adService: SponsoredBreakHumorAdService(settings: _deviceAds),
      adsSettings: _deviceAds,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Sponsorlu'), findsNothing);
    expect(controller.state.sessionAdCount, 0);

    for (var i = 0; i < 4; i++) {
      expect(find.text('Sponsorlu'), findsNothing);
      expect(controller.state.adsBlocked, isFalse);
      await _advanceFunny(tester, controller);
    }
    expect(controller.state.sessionAdCount, 0);

    await _advanceFunny(tester, controller);
    await _waitForSponsoredBreak(tester);
    expect(controller.state.feedLocked, isTrue);
    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));

    await _dismissSponsoredBreak(tester);
    expect(controller.state.sessionAdCount, 1);
    expect(controller.state.adsBlocked, isFalse);

    for (var i = 0; i < 4; i++) {
      expect(find.text('Sponsorlu'), findsNothing);
      await _advanceFunny(tester, controller);
    }

    await _advanceFunny(tester, controller);
    await _waitForSponsoredBreak(tester);
    await _dismissSponsoredBreak(tester);
    expect(controller.state.sessionAdCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Faz 6: premium mock — 10 content views, zero ads', (
    tester,
  ) async {
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed();
    final source = MockHumorDataSource(seed: seed);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adService: SponsoredBreakHumorAdService(settings: _deviceAds),
      adsSettings: _deviceAds,
      subscriptionRepository: _ReplayPremiumRepo(
        const PremiumStatus(isPremium: true),
      ),
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(controller.state.isPremium, isTrue);
    for (var i = 0; i < 10; i++) {
      expect(find.text('Sponsorlu'), findsNothing);
      await _advanceFunny(tester, controller);
    }
    expect(controller.state.sessionAdCount, 0);
  });

  testWidgets('Faz 6: free → premium transition clears ad gate', (
    tester,
  ) async {
    final updates = StreamController<PremiumStatus>.broadcast();
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 8);
    final source = MockHumorDataSource(seed: seed);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adService: SponsoredBreakHumorAdService(settings: _deviceAds),
      adsSettings: _deviceAds,
      subscriptionRepository: _ReplayPremiumRepo(
        const PremiumStatus(),
        updates,
      ),
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    for (var i = 0; i < 5; i++) {
      await _advanceFunny(tester, controller);
    }
    expect(controller.state.adsBlocked, isTrue);

    updates.add(const PremiumStatus(isPremium: true));
    await tester.pumpAndSettle();
    expect(controller.state.isPremium, isTrue);
    expect(controller.state.adPhase, HumorAdPhase.idle);
    expect(find.text('Sponsorlu'), findsNothing);

    for (var i = 0; i < 5; i++) {
      await _advanceFunny(tester, controller);
      expect(find.text('Sponsorlu'), findsNothing);
    }
    await updates.close();
  });

  testWidgets('Faz 6: background/resume during sponsored break', (
    tester,
  ) async {
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 8);
    final source = MockHumorDataSource(seed: seed);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adService: SponsoredBreakHumorAdService(settings: _deviceAds),
      adsSettings: _deviceAds,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    for (var i = 0; i < 5; i++) {
      await _advanceFunny(tester, controller);
    }
    await _waitForSponsoredBreak(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Sponsorlu'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dismissSponsoredBreak(tester);
    expect(controller.state.adsBlocked, isFalse);
  });

  testWidgets('Faz 6: ad failure soft-resumes feed', (tester) async {
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 8);
    final source = MockHumorDataSource(seed: seed);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adService: _FailingAdService(),
      adsSettings: _deviceAds,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    for (var i = 0; i < 5; i++) {
      await _advanceFunny(tester, controller);
    }
    await tester.pumpAndSettle();
    expect(controller.state.adsBlocked, isFalse);
    expect(controller.state.adPhase, HumorAdPhase.idle);
    expect(find.text('Sponsorlu'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Faz 6: rating after ad + interaction count excludes ads', (
    tester,
  ) async {
    final education = await _educationStore();
    final seed = await _loadYoutubeSeed(minCount: 8);
    final source = MockHumorDataSource(seed: seed);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adService: SponsoredBreakHumorAdService(settings: _deviceAds),
      adsSettings: _deviceAds,
      isPremium: false,
    );

    await _pumpHumorLab(tester, controller: controller, education: education);
    await controller.load();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final before = source.profile.interactionCount;
    for (var i = 0; i < 5; i++) {
      await _advanceFunny(tester, controller);
    }
    await _waitForSponsoredBreak(tester);
    await _dismissSponsoredBreak(tester);

    expect(source.profile.interactionCount, before + 5);
    expect(source.feedbackCalls, 5);

    await _advanceFunny(tester, controller);
    expect(source.profile.interactionCount, before + 6);
    expect(tester.takeException(), isNull);
  });
}
