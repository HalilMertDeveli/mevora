import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/humor_runtime_config.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/data/services/admob_interstitial_humor_ad_service.dart';
import 'package:mevora/features/humor/data/services/sponsored_break_humor_ad_service.dart';
import 'package:mevora/features/humor/domain/config/humor_ad_network_config.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

class HumorServices {
  const HumorServices({
    required this.repository,
    this.adService = const NoopHumorAdService(),
    this.subscriptionRepository,
    this.adsSettings = HumorAdsSettings.defaults,
  });

  final HumorRepository repository;
  final HumorAdService adService;
  final SubscriptionRepository? subscriptionRepository;
  final HumorAdsSettings adsSettings;
}

HumorAdService resolveHumorAdService({
  required HumorAdsSettings settings,
  required bool isProduction,
  HumorAdService? override,
}) {
  if (override != null) return override;
  if (!settings.enabled) return const NoopHumorAdService();
  if (settings.provider == 'mevora_sponsored_break') {
    return SponsoredBreakHumorAdService(settings: settings);
  }
  return AdMobInterstitialHumorAdService(
    config: HumorAdNetworkConfig.resolve(isProduction: isProduction),
  );
}

/// Mock only in debug development unless `--dart-define=USE_MOCK_HUMOR` overrides.
/// Staging/production release builds use real Cloud Functions by default.
HumorServices createHumorServices({
  AppConfig? config,
  BackendCallable? backend,
  HumorRepository? repository,
  HumorAdService? adService,
  SubscriptionRepository? subscriptionRepository,
  HumorAdsSettings? adsSettings,
}) {
  final settings = adsSettings ?? HumorAdsSettings.defaults;
  final environment = config?.environment ?? AppEnvironment.production;
  final ads = resolveHumorAdService(
    settings: settings,
    isProduction: environment.isProduction,
    override: adService,
  );

  if (repository != null) {
    return HumorServices(
      repository: repository,
      adService: ads,
      subscriptionRepository: subscriptionRepository,
      adsSettings: settings,
    );
  }
  final useMock = resolveUseMockHumor(environment);
  if (useMock) {
    return HumorServices(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource()),
      adService: ads,
      subscriptionRepository: subscriptionRepository,
      adsSettings: settings,
    );
  }
  return HumorServices(
    repository: HumorRepositoryImpl(
      dataSource: FunctionsHumorDataSource(
        backend: backend ??
            FirebaseFunctionsCallable(
              region: config?.functionsRegion ?? 'europe-west1',
            ),
      ),
    ),
    adService: ads,
    subscriptionRepository: subscriptionRepository,
    adsSettings: settings,
  );
}
