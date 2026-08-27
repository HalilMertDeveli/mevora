import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

class _FakeAdService implements HumorAdService {
  var showCalls = 0;
  HumorAdResult result = HumorAdResult.completedOk;

  @override
  bool get isAvailable => true;

  @override
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  }) async {
    showCalls += 1;
    return result;
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
  const tightAds = HumorAdsSettings(
    enabled: true,
    contentInterval: 3,
    minInterval: 3,
    maxInterval: 3,
    minWatchSeconds: 1,
    cooldownSeconds: 0,
  );

  HumorController buildController({
    MockHumorDataSource? source,
    HumorAdService? adService,
    bool isPremium = false,
    SubscriptionRepository? subscriptionRepository,
    HumorAdsSettings adsSettings = tightAds,
  }) {
    return HumorController(
      repository: HumorRepositoryImpl(
        dataSource: source ?? MockHumorDataSource(),
      ),
      adService: adService,
      adsSettings: adsSettings,
      isPremium: isPremium,
      subscriptionRepository: subscriptionRepository,
    );
  }

  test('load populates feed from mock datasource', () async {
    final source = MockHumorDataSource();
    final controller = buildController(source: source);

    await controller.load();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.failure, isNull);
    expect(controller.state.items, isNotEmpty);
    expect(controller.state.current?.contentId, 'hc_tr_vid_001');
    expect(controller.state.current?.type, HumorContentType.video);
    expect(controller.state.current?.language, 'tr');
    expect(controller.state.current?.hasMedia, isTrue);
    expect(source.feedCalls, 1);
  });

  test('rate advances index and enables undo', () async {
    final source = MockHumorDataSource();
    final controller = buildController(source: source);
    await controller.load();

    await controller.rate(HumorRating.veryFunny);

    expect(controller.state.currentIndex, 1);
    expect(controller.state.canUndo, isTrue);
    expect(controller.state.lastRated, HumorRating.veryFunny);
    expect(source.feedbackCalls, 1);
    expect(source.profile.interactionCount, 1);
  });

  test('undo returns to previous item', () async {
    final source = MockHumorDataSource();
    final controller = buildController(source: source);
    await controller.load();
    await controller.rate(HumorRating.funny);
    expect(controller.state.currentIndex, 1);

    await controller.undo();

    expect(controller.state.currentIndex, 0);
    expect(controller.state.canUndo, isFalse);
  });

  test('empty feed surfaces empty state', () async {
    final source = MockHumorDataSource(seed: const <HumorContent>[]);
    final controller = buildController(source: source);

    await controller.load();

    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.items, isEmpty);
  });

  test('feed error surfaces failure', () async {
    final source = MockHumorDataSource()..failFeed = true;
    final controller = buildController(source: source);

    await controller.load();

    expect(controller.state.failure, isNotNull);
    expect(controller.state.items, isEmpty);
    expect(controller.state.isLoading, isFalse);
  });

  test('free user becomes ad-eligible after interval and resumes after ad', () async {
    final ads = _FakeAdService();
    final controller = buildController(adService: ads);
    await controller.load();

    // View/rate through interval (3) — first item counted on load.
    await controller.rate(HumorRating.funny); // -> index 1
    await controller.rate(HumorRating.funny); // -> index 2
    expect(controller.state.adPhase, HumorAdPhase.idle);

    await controller.rate(HumorRating.funny); // after 3 views, gate before advance
    expect(controller.state.adPhase, HumorAdPhase.eligible);
    expect(controller.state.adsBlocked, isTrue);
    expect(ads.showCalls, 0);

    await controller.presentPendingAd();
    expect(ads.showCalls, 1);
    expect(controller.state.adPhase, HumorAdPhase.idle);
    expect(controller.state.adsBlocked, isFalse);
    expect(controller.state.sessionAdCount, 1);
    expect(controller.state.currentIndex, greaterThanOrEqualTo(3));
  });

  test('premium user never shows ads across many content advances', () async {
    final ads = _FakeAdService();
    final controller = buildController(adService: ads, isPremium: true);
    await controller.load();

    for (var i = 0; i < 20; i++) {
      await controller.rate(HumorRating.funny);
      expect(controller.state.adPhase, HumorAdPhase.idle);
      expect(controller.state.sessionAdCount, 0);
    }
    expect(ads.showCalls, 0);
  });

  test('ad failure soft-resumes feed without lock', () async {
    final controller = buildController(adService: _FailingAdService());
    await controller.load();
    await controller.rate(HumorRating.funny);
    await controller.rate(HumorRating.funny);
    await controller.rate(HumorRating.funny);
    expect(controller.state.adPhase, HumorAdPhase.eligible);

    await controller.presentPendingAd();
    expect(controller.state.adsBlocked, isFalse);
    expect(controller.state.adPhase, HumorAdPhase.idle);
  });

  test('duplicate ad requests are ignored while in flight', () async {
    final ads = _FakeAdService();
    final controller = buildController(adService: ads);
    await controller.load();
    await controller.rate(HumorRating.funny);
    await controller.rate(HumorRating.funny);
    await controller.rate(HumorRating.funny);
    expect(controller.state.adPhase, HumorAdPhase.eligible);

    final first = controller.presentPendingAd();
    final second = controller.presentPendingAd();
    await Future.wait([first, second]);
    expect(ads.showCalls, 1);
  });

  test('premium upgrade mid-session clears ad gate', () async {
    final premium = StreamController<PremiumStatus>.broadcast();
    final repo = _StreamPremiumRepo(premium.stream);
    final ads = _FakeAdService();
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource()),
      adService: ads,
      adsSettings: tightAds,
      subscriptionRepository: repo,
    );
    await controller.load();
    await controller.rate(HumorRating.funny);
    await controller.rate(HumorRating.funny);
    await controller.rate(HumorRating.funny);
    expect(controller.state.adPhase, HumorAdPhase.eligible);

    premium.add(const PremiumStatus(isPremium: true));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isPremium, isTrue);
    expect(controller.state.adPhase, HumorAdPhase.idle);
    expect(controller.state.adsBlocked, isFalse);
    await premium.close();
  });

  test('infinite prefetch keeps nextCursor after first page', () async {
    final source = MockHumorDataSource();
    final controller = buildController(
      source: source,
      adsSettings: const HumorAdsSettings(enabled: false),
    );
    await controller.load();
    expect(controller.state.hasMore, isTrue);
    final firstCount = controller.state.items.length;

    // Force prefetch by advancing near end.
    for (var i = 0; i < firstCount - 1; i++) {
      await controller.rate(HumorRating.neutral);
    }
    expect(source.feedCalls, greaterThan(1));
    expect(controller.state.items.length, greaterThanOrEqualTo(firstCount));
    expect(controller.state.hasMore, isTrue);
  });
}

class _StreamPremiumRepo implements SubscriptionRepository {
  _StreamPremiumRepo(this._stream);
  final Stream<PremiumStatus> _stream;

  @override
  Stream<PremiumStatus> watch() => _stream;
}
