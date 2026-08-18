import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:mevora/app.dart';
import 'package:mevora/core/analytics/firebase_analytics_adapter.dart';
import 'package:mevora/core/analytics/noop_analytics_provider.dart';
import 'package:mevora/core/cache/image_cache_policy.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/di/boost_services_factory.dart';
import 'package:mevora/core/di/discovery_services_factory.dart';
import 'package:mevora/core/di/location_services_factory.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/errors/error_handler.dart';
import 'package:mevora/core/identity/firebase_auth_uid_source.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/presentation/pages/firebase_unavailable_app.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/firebase/firebase_bootstrap.dart';
import 'package:mevora/core/services/firebase/firebase_crash_reporter.dart';
import 'package:mevora/core/services/permissions/permission_handler_permission_service.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/auth_composition.dart';
import 'package:mevora/features/location/data/location_analytics.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/notifications/data/fcm_background.dart';
import 'package:mevora/features/settings/data/datasources/firebase_settings_data_source.dart';
import 'package:mevora/features/settings/data/repositories/user_settings_repository_impl.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootstrap(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();
  ImageCachePolicy.apply();

  final config = AppConfig(environment: environment);
  final logger = AppLogger(environment: environment);

  try {
    await FirebaseBootstrap(logger: logger).initialize(config);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } on Object catch (error, stackTrace) {
    logger.error(
      'Firebase initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(const MevoraStartupErrorApp());
    return;
  }

  ErrorHandler.register(
    logger: logger,
    crashReporter: const FirebaseCrashReporter(),
  );
  ErrorWidget.builder = (details) {
    return Theme(
      data: AppTheme.light(),
      child: const MevoraErrorView(),
    );
  };

  final authController = createAuthController(config: config, logger: logger);
  const permissionService = PermissionHandlerPermissionService();
  final locationServices = createLocationServices(
    logger: logger,
    permissions: permissionService,
  );
  final discoveryServices = createDiscoveryServices();
  final socialServices = createFirebaseSocialServices();
  final analytics = environment.isProduction
      ? FirebaseAnalyticsAdapter()
      : NoopAnalyticsProvider(logger: logger);
  final locationController = LocationController(
    repository: locationServices.locationRepository,
    analytics: AnalyticsLocationAnalytics(analytics),
  );
  final boostServices = createBoostServices(
    uidSource: FirebaseAuthUidSource(),
    logger: logger,
  );
  final languageController = LanguageController(
    repository: LanguageRepository(
      local: SharedPreferencesLanguageDataSource(
        preferences: await SharedPreferences.getInstance(),
      ),
      remote: UserSettingsRepositoryImpl(
        dataSource: FirebaseSettingsDataSource(),
      ),
    ),
    authLocaleBinder: FirebaseAuth.instance.setLanguageCode,
    analytics: analytics,
  );
  await languageController.load();

  logger.info('Starting ${config.appName}');
  runApp(
    MevoraApp(
      config: config,
      logger: logger,
      authController: authController,
      locationRepository: locationServices.locationRepository,
      locationController: locationController,
      discoveryRepository: discoveryServices.discoveryRepository,
      socialServices: socialServices,
      purchaseRepository: boostServices.purchaseRepository,
      analytics: analytics,
      languageController: languageController,
      permissionService: permissionService,
    ),
  );
}
