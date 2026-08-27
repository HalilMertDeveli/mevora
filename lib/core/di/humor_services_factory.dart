import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/data/services/sponsored_break_humor_ad_service.dart';
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

/// Prefer mock by default for MVP local UI safety.
/// Pass `--dart-define=USE_MOCK_HUMOR=false` to hit Cloud Functions.
HumorServices createHumorServices({
  AppConfig? config,
  BackendCallable? backend,
  HumorRepository? repository,
  HumorAdService? adService,
  SubscriptionRepository? subscriptionRepository,
  HumorAdsSettings? adsSettings,
}) {
  final settings = adsSettings ?? HumorAdsSettings.defaults;
  final ads = adService ??
      (settings.enabled
          ? SponsoredBreakHumorAdService(settings: settings)
          : const NoopHumorAdService());

  if (repository != null) {
    return HumorServices(
      repository: repository,
      adService: ads,
      subscriptionRepository: subscriptionRepository,
      adsSettings: settings,
    );
  }
  const useMock = bool.fromEnvironment(
    'USE_MOCK_HUMOR',
    defaultValue: true,
  );
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
