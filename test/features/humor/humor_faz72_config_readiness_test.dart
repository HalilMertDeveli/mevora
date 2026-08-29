import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/config/humor_ad_network_config.dart';
import 'package:mevora/features/subscription/domain/config/premium_pack_catalog.dart';

void main() {
  group('FAZ 7.2 production config readiness', () {
    test('non-production always uses Google sample AdMob IDs', () {
      final config = HumorAdNetworkConfig.resolve(isProduction: false);
      expect(config.useTestIds, isTrue);
      expect(config.androidAppId, HumorAdNetworkConfig.googleTestAndroidAppId);
      expect(config.iosAppId, HumorAdNetworkConfig.googleTestIosAppId);
      expect(
        config.androidInterstitialUnitId,
        HumorAdNetworkConfig.googleTestAndroidInterstitial,
      );
      expect(
        config.iosInterstitialUnitId,
        HumorAdNetworkConfig.googleTestIosInterstitial,
      );
      expect(config.hasProductionAppIdConfigured, isFalse);
      expect(config.hasProductionUnitConfigured, isFalse);
    });

    test(
      'production without dart-defines stays NOT CONFIGURED (sample fallback)',
      () {
        final config = HumorAdNetworkConfig.resolve(isProduction: true);
        expect(config.useTestIds, isFalse);
        expect(config.hasProductionAppIdConfigured, isFalse);
        expect(config.hasProductionUnitConfigured, isFalse);
      },
    );

    test('premium SKUs remain duration-pack product ids', () {
      expect(
        PremiumPackCatalog.productIds,
        ['mevora_premium_1_month', 'mevora_premium_1_year'],
      );
      expect(PremiumPackCatalog.durationDaysFor(PremiumPackCatalog.month), 30);
      expect(PremiumPackCatalog.durationDaysFor(PremiumPackCatalog.year), 365);
    });
  });
}
