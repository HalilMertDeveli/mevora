import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:mevora/app.dart';
import 'package:mevora/core/analytics/firebase_analytics_adapter.dart';
import 'package:mevora/core/analytics/noop_analytics_provider.dart';
import 'package:mevora/core/cache/image_cache_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/build_guards.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/core/di/boost_services_factory.dart';
import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/di/discovery_services_factory.dart';
import 'package:mevora/core/di/location_services_factory.dart';
import 'package:mevora/core/di/music_services_factory.dart';
import 'package:mevora/core/di/humor_services_factory.dart';
import 'package:mevora/core/di/relationship_services_factory.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/di/support_scope.dart';
import 'package:mevora/core/di/subscription_services_factory.dart';
import 'package:mevora/core/di/streak_services_factory.dart';
import 'package:mevora/core/di/face_anchor_services_factory.dart';
import 'package:mevora/core/di/verification_services_factory.dart';
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
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/authentication/data/services/reauth_service.dart';
import 'package:mevora/features/location/data/location_analytics.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/notifications/data/fcm_background.dart';
import 'package:mevora/features/settings/data/datasources/firebase_settings_data_source.dart';
import 'package:mevora/features/settings/data/repositories/user_settings_repository_impl.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootstrap(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();
  ImageCachePolicy.apply();

  final config = AppConfig(
    environment: environment,
    featureFlags: FeatureFlags(
      humorLabEnabled: resolveHumorLabEnabled(environment),
      premiumEnabled: resolvePremiumEnabled(environment),
    ),
  );
  final logger = AppLogger(environment: environment);

  // Refuse to run a flavor from another environment's entrypoint — most
  // importantly a production-flavor build started from lib/main.dart, which
  // is the development environment.
  final flavorMismatch = flavorEnvironmentMismatch(
    flavor: appFlavor,
    environment: environment,
  );
  if (flavorMismatch != null) {
    logger.error(flavorMismatch);
    runApp(const MevoraStartupErrorApp());
    return;
  }

  // The same for a build that was handed development-only settings: they
  // would do nothing here, but they would be in the binary.
  final leakedDefines = developmentDefinesOutsideDevelopment(
    environment: environment,
    passed: developmentDefinesPassed(),
  );
  if (leakedDefines != null) {
    logger.error(leakedDefines);
    runApp(const MevoraStartupErrorApp());
    return;
  }

  try {
    await FirebaseBootstrap(logger: logger).initialize(config);
    if (!environment.isDevelopment) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
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
    return Theme(data: AppTheme.light(), child: const MevoraErrorView());
  };

  final spotifyAuthService = SpotifyAuthService(config: config);
  final authController = createAuthController(
    config: config,
    logger: logger,
    spotifyAuthService: spotifyAuthService,
  );
  final googleAuth = GoogleAuthService(
    serverClientId: config.googleWebClientId,
  );
  final settingsServices = createSettingsServices(
    reauthService: ReauthService(googleAuthService: googleAuth),
  );
  const permissionService = PermissionHandlerPermissionService();
  final locationServices = createLocationServices(
    logger: logger,
    permissions: permissionService,
  );
  final uidSource = FirebaseAuthUidSource();
  // Demo matches exist for the development demo deck only. Outside it there
  // is no hub, and the social repositories are the real ones with nothing in
  // front of them.
  // `!kReleaseMode` is written out, not left to the guard: it is a
  // compile-time constant, so in a release build the compiler can see that
  // the demo hub is never built and leaves the whole demo layer out of the
  // binary.
  final demoAllowed =
      !kReleaseMode && demoInfrastructureAllowed(environment: environment);
  MevoraPhotoImages.demoPortraitsAvailable = demoAllowed;
  final demoHub = demoAllowed ? DemoSocialHub(uidSource: uidSource) : null;
  final discoveryServices = createDiscoveryServices(
    config: config,
    demoHub: demoHub,
    currentUid: () => uidSource.currentUid ?? 'self',
  );
  final musicServices = createMusicServices(
    config: config,
    spotifyAuthService: spotifyAuthService,
  );
  final humorServices = createHumorServices(config: config);
  final relationshipServices = createRelationshipServices(config: config);
  final socialServices = createFirebaseSocialServices(
    uidSource: uidSource,
    demoHub: demoHub,
  );
  final supportServices = createSupportServices();
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
    useEmulatorStore: config.useEmulators,
    environment: environment,
  );
  final verificationServices = createVerificationServices();
  final faceAnchorServices = createFaceAnchorServices();
  final subscriptionServices = createSubscriptionServices(
    uidSource: uidSource,
    premiumEnabled: config.featureFlags.premiumEnabled,
    analytics: analytics,
    logger: logger,
    useEmulatorStore: config.useEmulators,
    environment: environment,
  );
  final streakServices = createStreakServices(
    analytics: analytics,
    logger: logger,
  );
  final preferences = await SharedPreferences.getInstance();
  final appOperations = createAppOperationsController(
    preferences: preferences,
    logger: logger,
  );
  final languageController = LanguageController(
    repository: LanguageRepository(
      local: SharedPreferencesLanguageDataSource(preferences: preferences),
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
      musicRepository: musicServices.repository,
      humorRepository: humorServices.repository,
      relationshipRepository: relationshipServices.repository,
      profileQuestionAnswerRepository: relationshipServices.profileAnswers,
      relationshipLearningRepository: relationshipServices.learning,
      socialServices: socialServices,
      purchaseRepository: boostServices.purchaseRepository,
      subscriptionServices: subscriptionServices,
      verificationRepository: verificationServices.repository,
      faceAnchorServices: faceAnchorServices,
      analytics: analytics,
      languageController: languageController,
      permissionService: permissionService,
      settingsServices: settingsServices,
      supportServices: supportServices,
      streakServices: streakServices,
      appOperations: appOperations,
    ),
  );
}

/// Humor Lab flag resolution:
/// - `--dart-define=HUMOR_LAB_ENABLED=true|false` forces the value
/// - otherwise: ON in debug development builds (manual device QA), OFF elsewhere
bool resolveHumorLabEnabled(AppEnvironment environment) {
  const forced = String.fromEnvironment('HUMOR_LAB_ENABLED', defaultValue: '');
  if (forced == 'true') {
    return true;
  }
  if (forced == 'false') {
    return false;
  }
  return environment.isDevelopment && kDebugMode;
}

/// Premium flag resolution, the same shape as Humor Lab's:
/// - `--dart-define=PREMIUM_ENABLED=true|false` forces the value
/// - otherwise: ON in debug development builds (manual device QA), OFF elsewhere
///
/// This switches the Premium *surface* on — the paywall and its entry point.
/// It grants nobody anything: entitlement is still whatever the server wrote.
bool resolvePremiumEnabled(AppEnvironment environment) {
  const forced = String.fromEnvironment('PREMIUM_ENABLED', defaultValue: '');
  if (forced == 'true') {
    return true;
  }
  if (forced == 'false') {
    return false;
  }
  return environment.isDevelopment && kDebugMode;
}
