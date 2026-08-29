import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_policy.dart';

void main() {
  test('HumorAdsSettings defaults use 5-content interval', () {
    expect(HumorAdsSettings.defaults.effectiveInterval, 5);
    expect(HumorAdsSettings.defaults.minContentBeforeFirstAd, 5);
    expect(HumorAdsSettings.defaults.provider, 'admob_interstitial');
  });

  test('HumorAdsSettings clamps interval', () {
    expect(
      const HumorAdsSettings(contentInterval: 2, minInterval: 5, maxInterval: 20)
          .effectiveInterval,
      5,
    );
    expect(
      const HumorAdsSettings(contentInterval: 99, minInterval: 5, maxInterval: 20)
          .effectiveInterval,
      20,
    );
  });

  test('HumorAdsSettings fromJson preserves minContentBeforeFirstAd', () {
    final parsed = HumorAdsSettings.fromJson({
      'contentInterval': 6,
      'minContentBeforeFirstAd': 4,
    });
    expect(parsed.contentInterval, 6);
    expect(parsed.minContentBeforeFirstAd, 4);
  });

  test('premium never eligible', () {
    final policy = HumorAdPolicyController(
      settings: const HumorAdsSettings(contentInterval: 1, minInterval: 1),
    );
    policy.onContentViewed();
    expect(policy.isEligible(isPremium: true), isFalse);
  });

  test('first ad not before minContentBeforeFirstAd', () {
    final policy = HumorAdPolicyController(
      settings: const HumorAdsSettings(
        contentInterval: 1,
        minInterval: 1,
        minContentBeforeFirstAd: 5,
        cooldownSeconds: 0,
      ),
    );
    for (var i = 0; i < 4; i++) {
      policy.onContentViewed();
      expect(policy.isEligible(isPremium: false), isFalse);
    }
    policy.onContentViewed();
    expect(policy.isEligible(isPremium: false), isTrue);
  });

  test('free user eligible after interval and cooldown', () {
    final policy = HumorAdPolicyController(
      settings: const HumorAdsSettings(
        contentInterval: 2,
        minInterval: 2,
        maxInterval: 2,
        minContentBeforeFirstAd: 2,
        cooldownSeconds: 60,
      ),
    );
    policy.onContentViewed();
    expect(policy.isEligible(isPremium: false), isFalse);
    policy.onContentViewed();
    expect(policy.isEligible(isPremium: false), isTrue);
    policy.markAdStarted();
    expect(policy.isEligible(isPremium: false), isFalse);
    policy.markAdFinished(completed: true);
    policy.onContentViewed();
    policy.onContentViewed();
    // Cooldown still active.
    expect(policy.isEligible(isPremium: false), isFalse);
  });
}
