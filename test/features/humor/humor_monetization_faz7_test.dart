import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/humor_services_factory.dart';
import 'package:mevora/features/humor/data/services/admob_interstitial_humor_ad_service.dart';
import 'package:mevora/features/humor/data/services/sponsored_break_humor_ad_service.dart';
import 'package:mevora/features/humor/domain/config/humor_ad_network_config.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/subscription/domain/config/premium_pack_catalog.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_purchase_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

void main() {
  test('HumorAdNetworkConfig uses Google test IDs outside production', () {
    final config = HumorAdNetworkConfig.resolve(isProduction: false);
    expect(config.useTestIds, isTrue);
    expect(config.androidAppId, HumorAdNetworkConfig.googleTestAndroidAppId);
    expect(
      config.androidInterstitialUnitId,
      HumorAdNetworkConfig.googleTestAndroidInterstitial,
    );
  });

  test('resolveHumorAdService picks AdMob for default provider', () {
    final service = resolveHumorAdService(
      settings: HumorAdsSettings.defaults,
      isProduction: false,
    );
    expect(service, isA<AdMobInterstitialHumorAdService>());
  });

  test('resolveHumorAdService keeps sponsored break when configured', () {
    final service = resolveHumorAdService(
      settings: const HumorAdsSettings(provider: 'mevora_sponsored_break'),
      isProduction: false,
    );
    expect(service, isA<SponsoredBreakHumorAdService>());
  });

  test('resolveHumorAdService respects noop when disabled', () {
    final service = resolveHumorAdService(
      settings: const HumorAdsSettings(enabled: false),
      isProduction: true,
    );
    expect(service, isA<NoopHumorAdService>());
  });

  test('HumorAdNetworkConfig production without defines stays on sample IDs', () {
    final config = HumorAdNetworkConfig.resolve(isProduction: true);
    expect(config.useTestIds, isFalse);
    // Without dart-defines, production falls back to sample (policy-safe).
    expect(config.hasProductionUnitConfigured, isFalse);
    expect(config.hasProductionAppIdConfigured, isFalse);
  });

  test('PremiumPackCatalog SKUs are stable', () {
    expect(PremiumPackCatalog.productIds, contains('mevora_premium_1_month'));
    expect(PremiumPackCatalog.durationDaysFor(PremiumPackCatalog.year), 365);
  });

  test('PremiumPurchaseController maps cancel and pending states', () async {
    final repo = _FakePremiumRepo()
      ..purchaseResult = const Err(UnexpectedFailure('purchase_cancelled'));
    final controller = PremiumPurchaseController(repository: repo);
    await controller.buyMonth();
    expect(controller.state, PremiumPurchaseUiState.cancelled);

    repo.purchaseResult = const Err(UnexpectedFailure('purchase_pending'));
    await controller.buyMonth();
    expect(controller.state, PremiumPurchaseUiState.pending);
  });

  test('PremiumPurchaseController success stores entitlement status', () async {
    final repo = _FakePremiumRepo()
      ..purchaseResult = const Success(
        PremiumPurchaseResult(
          productId: PremiumPackCatalog.month,
          alreadyProcessed: false,
          status: PremiumStatus(isPremium: true),
        ),
      );
    final controller = PremiumPurchaseController(repository: repo);
    await controller.buyMonth();
    expect(controller.state, PremiumPurchaseUiState.success);
    expect(controller.lastStatus.isPremium, isTrue);
  });
}

class _FakePremiumRepo implements PremiumPurchaseRepository {
  Result<PremiumPurchaseResult> purchaseResult = const Err(
    UnexpectedFailure('purchase_failed'),
  );

  @override
  Future<Result<List<String>>> loadStoreProductIds() async {
    return const Success([PremiumPackCatalog.month]);
  }

  @override
  Future<Result<PremiumPurchaseResult>> purchase({
    required String productId,
  }) async {
    return purchaseResult;
  }

  @override
  Future<Result<List<PremiumPurchaseResult>>> restore() async {
    return const Success([]);
  }
}
