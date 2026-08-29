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
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

/// FAZ 7.2 host policy E2E (controller path — no physical device).

const _ads = HumorAdsSettings(
  contentInterval: 5,
  minInterval: 5,
  minContentBeforeFirstAd: 5,
  minWatchSeconds: 1,
  cooldownSeconds: 0,
  provider: 'admob_interstitial',
);

List<HumorContent> _seed(int count) {
  return List.generate(count, (i) {
    return HumorContent.sanitized(
      contentId: 'faz72_$i',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      provider: 'youtube',
      sourceId: 'dQw4w9WgXcQ',
      embedUrl: 'https://www.youtube.com/embed/dQw4w9WgXcQ?playsinline=1',
      thumbUrl: 'https://example.invalid/t$i.jpg',
      downloadUrl: 'https://example.invalid/t$i.jpg',
      attributionRequired: true,
      aspectRatio: 9 / 16,
    );
  });
}

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
    return HumorAdResult.completedOk;
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
    return const HumorAdResult(
      completed: false,
      failed: true,
      errorCode: 'simulated_no_fill',
    );
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

Future<void> _rateAndGate(HumorController c) async {
  await c.rate(HumorRating.funny);
  // Drain unawaited advance + optional ad presentation (page would do this).
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
    if (c.state.adPhase == HumorAdPhase.eligible) {
      await c.presentPendingAd();
    }
    if (!c.state.adsBlocked) {
      break;
    }
  }
}

void main() {
  test('FAZ 7.2 policy free — entry no ad, 5th ad, second cycle', () async {
    final ads = _AutoCompleteAdService();
    final controller = HumorController(
      repository: HumorRepositoryImpl(
        dataSource: MockHumorDataSource(seed: _seed(24)),
      ),
      adService: ads,
      adsSettings: _ads,
      isPremium: false,
    );
    await controller.load();
    expect(controller.state.sessionAdCount, 0);

    for (var i = 0; i < 4; i++) {
      await _rateAndGate(controller);
      expect(controller.state.sessionAdCount, 0, reason: 'no ad before 5th');
      expect(controller.state.adsBlocked, isFalse);
    }

    await _rateAndGate(controller);
    expect(controller.state.sessionAdCount, 1);
    expect(ads.showCount, 1);
    expect(controller.state.adsBlocked, isFalse);

    for (var i = 0; i < 4; i++) {
      await _rateAndGate(controller);
      expect(controller.state.sessionAdCount, 1);
    }
    await _rateAndGate(controller);
    expect(controller.state.sessionAdCount, 2);
    expect(ads.showCount, 2);
    expect(controller.state.adsBlocked, isFalse);
    controller.dispose();
  });

  test('FAZ 7.2 policy premium fixture — 10 content no ads', () async {
    final premium = _MutablePremiumRepo(const PremiumStatus(isPremium: true));
    final ads = _AutoCompleteAdService();
    final controller = HumorController(
      repository: HumorRepositoryImpl(
        dataSource: MockHumorDataSource(seed: _seed(16)),
      ),
      adService: ads,
      adsSettings: _ads,
      subscriptionRepository: premium,
      isPremium: true,
    );
    await controller.load();
    for (var i = 0; i < 10; i++) {
      await _rateAndGate(controller);
      expect(controller.state.sessionAdCount, 0);
      expect(ads.showCount, 0);
    }
    controller.dispose();
    await premium.dispose();
  });

  test('FAZ 7.2 policy free→premium stops ads', () async {
    final premium = _MutablePremiumRepo(const PremiumStatus(isPremium: false));
    final ads = _AutoCompleteAdService();
    final controller = HumorController(
      repository: HumorRepositoryImpl(
        dataSource: MockHumorDataSource(seed: _seed(20)),
      ),
      adService: ads,
      adsSettings: _ads,
      subscriptionRepository: premium,
      isPremium: false,
    );
    await controller.load();
    for (var i = 0; i < 5; i++) {
      await _rateAndGate(controller);
    }
    expect(controller.state.sessionAdCount, 1);
    premium.setPremium(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isPremium, isTrue);
    final before = ads.showCount;
    for (var i = 0; i < 6; i++) {
      await _rateAndGate(controller);
      expect(controller.state.adsBlocked, isFalse);
    }
    expect(ads.showCount, before);
    controller.dispose();
    await premium.dispose();
  });

  test('FAZ 7.2 policy soft-fail unlocks feed', () async {
    final controller = HumorController(
      repository: HumorRepositoryImpl(
        dataSource: MockHumorDataSource(seed: _seed(12)),
      ),
      adService: _FailingAdService(),
      adsSettings: _ads,
      isPremium: false,
    );
    await controller.load();
    for (var i = 0; i < 6; i++) {
      await _rateAndGate(controller);
      expect(controller.state.adsBlocked, isFalse);
      expect(controller.state.feedLocked, isFalse);
    }
    controller.dispose();
  });
}
