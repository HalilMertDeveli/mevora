import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_policy.dart';

void main() {
  test('HumorAdsSettings clamps interval', () {
    expect(
      const HumorAdsSettings(contentInterval: 2, minInterval: 8, maxInterval: 20)
          .effectiveInterval,
      8,
    );
    expect(
      const HumorAdsSettings(contentInterval: 99, minInterval: 8, maxInterval: 20)
          .effectiveInterval,
      20,
    );
  });

  test('premium never eligible', () {
    final policy = HumorAdPolicyController(
      settings: const HumorAdsSettings(contentInterval: 1, minInterval: 1),
    );
    policy.onContentViewed();
    expect(policy.isEligible(isPremium: true), isFalse);
  });

  test('free user eligible after interval and cooldown', () {
    final policy = HumorAdPolicyController(
      settings: const HumorAdsSettings(
        contentInterval: 2,
        minInterval: 2,
        maxInterval: 2,
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
