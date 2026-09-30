import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/discovery_scope.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/core/di/onboarding_services_factory.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/support_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/core/di/subscription_services_factory.dart';
import 'package:mevora/core/di/streak_scope.dart';
import 'package:mevora/core/di/streak_services_factory.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/routing/app_router.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/permissions/permission_handler_permission_service.dart';
import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/core/session/session_recovery_controller.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/streak/presentation/controllers/daily_streak_controller.dart';
import 'package:mevora/features/app_operations/presentation/controllers/app_operations_controller.dart';
import 'package:mevora/features/app_operations/presentation/widgets/app_operations_banner_host.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_bootstrap_controller.dart';
import 'package:mevora/features/matching/presentation/controllers/presence_lifecycle_controller.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/notifications/data/fcm_push_binder.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/learning_journey_controller.dart';
import 'package:mevora/core/di/verification_scope.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';

class MevoraApp extends StatefulWidget {
  const MevoraApp({
    super.key,
    required this.config,
    required this.logger,
    required this.authController,
    this.router,
    this.locationRepository,
    this.discoveryRepository,
    this.musicRepository,
    this.humorRepository,
    this.relationshipRepository,
    this.profileQuestionAnswerRepository,
    this.relationshipLearningRepository,
    this.locationController,
    this.socialServices,
    this.purchaseRepository,
    this.subscriptionServices,
    this.verificationRepository,
    this.analytics,
    this.languageController,
    this.permissionService,
    this.permissionController,
    this.onboardingServices,
    this.settingsServices,
    this.supportServices,
    this.streakServices,
    this.appOperations,
  });

  final AppConfig config;
  final AppLogger logger;
  final AuthController authController;
  final GoRouter? router;
  final LocationRepository? locationRepository;
  final DiscoveryRepository? discoveryRepository;
  final MusicRepository? musicRepository;
  final HumorRepository? humorRepository;
  final RelationshipRepository? relationshipRepository;
  final ProfileQuestionAnswerRepository? profileQuestionAnswerRepository;
  final RelationshipLearningRepository? relationshipLearningRepository;
  final LocationController? locationController;
  final SocialServices? socialServices;
  final PurchaseRepository? purchaseRepository;
  final SubscriptionServices? subscriptionServices;
  final VerificationRepository? verificationRepository;
  final AnalyticsProvider? analytics;
  final LanguageController? languageController;
  final PermissionService? permissionService;
  final PermissionController? permissionController;
  final SettingsServices? settingsServices;
  final SupportServices? supportServices;
  final OnboardingServices? onboardingServices;
  final StreakServices? streakServices;

  /// Maintenance, update gates, announcements and feature switches. Null in
  /// tests and previews: the app then runs as in normal operation.
  final AppOperationsController? appOperations;

  @override
  State<MevoraApp> createState() => _MevoraAppState();
}

class _MevoraAppState extends State<MevoraApp> {
  late final GoRouter _router;
  LocationController? _locationController;
  LearningJourneyController? _journey;
  bool _ownsLocationController = false;
  FcmPushBinder? _pushBinder;
  late final LanguageController _languageController;
  bool _ownsLanguageController = false;
  late final PermissionService _permissionService;
  late final PermissionController _permissionController;
  bool _ownsPermissionController = false;
  late final OnboardingServices _onboardingServices;
  bool _ownsOnboardingServices = false;
  PresenceLifecycleController? _presenceLifecycleController;
  E2eeBootstrapController? _e2eeBootstrapController;
  SessionRecoveryController? _sessionRecovery;

  @override
  void initState() {
    super.initState();
    widget.authController.start();
    // Cached operations state applies at once; the live document follows.
    // Never awaited — nothing waits on the network for this.
    widget.appOperations
      ?..start()
      ..attachLifecycle();
    _sessionRecovery = SessionRecoveryController(logger: widget.logger)
      ..attach();
    unawaited(_sessionRecovery!.recover(reason: 'cold_start'));
    final providedLanguage = widget.languageController;
    if (providedLanguage != null) {
      _languageController = providedLanguage;
    } else {
      _languageController = LanguageController(
        repository: LanguageRepository(local: MemoryLanguageDataSource()),
        analytics: widget.analytics,
      );
      _ownsLanguageController = true;
      unawaited(_languageController.load());
    }
    final provided = widget.locationController;
    if (provided != null) {
      _locationController = provided;
    } else {
      final location = widget.locationRepository;
      if (location != null) {
        _locationController = LocationController(repository: location);
        _ownsLocationController = true;
      }
    }
    _locationController?.attachLifecycle();
    widget.authController.addListener(_syncLocationGate);
    widget.authController.addListener(_syncLanguageUser);
    _syncLocationGate();
    _syncLanguageUser();
    // Daily streak: checks in when a member is in the app and on resume.
    // Never awaited — the app does not wait on the streak for anything.
    widget.streakServices?.controller.attachLifecycle();
    widget.authController.addListener(_syncStreakUser);
    _syncStreakUser();
    _permissionService =
        widget.permissionService ?? const PermissionHandlerPermissionService();
    final providedPermissions = widget.permissionController;
    if (providedPermissions != null) {
      _permissionController = providedPermissions;
    } else {
      _permissionController = PermissionController(
        service: _permissionService,
        onNotificationsGranted: () async {
          await _pushBinder?.registerCurrentToken();
        },
      );
      _ownsPermissionController = true;
    }
    final providedOnboarding = widget.onboardingServices;
    if (providedOnboarding != null) {
      _onboardingServices = providedOnboarding;
    } else {
      _onboardingServices = createOnboardingServices();
      _ownsOnboardingServices = true;
    }
    final learning = widget.relationshipLearningRepository;
    if (learning != null) {
      _journey = LearningJourneyController(
        repository: learning,
        humorEnabled: widget.config.featureFlags.humorLabEnabled,
        analytics: widget.analytics,
      )..attachLifecycle();
      // Registered before the router's own listener, so the journey is
      // already pending when the router first sees a signed-in member.
      widget.authController.addListener(_syncJourney);
      _syncJourney();
    }
    _router =
        widget.router ??
        createAppRouter(
          config: widget.config,
          authController: widget.authController,
          locationController: _locationController,
          journey: _journey,
          appOperations: widget.appOperations,
        );
    final social = widget.socialServices;
    if (social != null) {
      _presenceLifecycleController = PresenceLifecycleController(
        presenceRepository: social.presenceRepository,
        uidSource: social.uidSource,
      )..attach();
      _e2eeBootstrapController = E2eeBootstrapController(
        uidSource: social.uidSource,
      )..attach();
      _pushBinder = FcmPushBinder(router: _router, services: social);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_pushBinder?.attach());
      });
    }
  }

  void _syncStreakUser() {
    final controller = widget.streakServices?.controller;
    if (controller == null) {
      return;
    }
    controller.bindUser(
      streakMemberUid(widget.authController.status, current: controller.uid),
    );
  }

  void _syncLocationGate() {
    unawaited(_locationController?.syncForUser(widget.authController.user?.id));
  }

  /// The first-run journey follows the signed-in member: read once their
  /// basic profile is complete, forgotten on sign-out.
  void _syncJourney() {
    final journey = _journey;
    if (journey == null) {
      return;
    }
    final status = widget.authController.status;
    if (status is Authenticated &&
        (status.user.onboardingCompleted || status.user.profileCompleted)) {
      journey.startFor(status.user.id);
    } else if (status is Unauthenticated) {
      journey.clear();
    }
  }

  void _syncLanguageUser() {
    final uid = widget.authController.user?.id;
    if (uid == null) {
      _languageController.detachUser();
      return;
    }
    unawaited(_languageController.attachUser(uid));
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ListenableBuilder(
      listenable: _languageController,
      builder: (context, _) {
        return MaterialApp.router(
          title: widget.config.appName,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.light,
          locale: _languageController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          localeResolutionCallback: (_, _) {
            return _languageController.locale;
          },
          routerConfig: _router,
          builder: (context, child) =>
              AppOperationsBannerHost(child: child ?? const SizedBox.shrink()),
          debugShowCheckedModeBanner: widget.config.showDebugBanner,
        );
      },
    );

    child = LanguageScope(controller: _languageController, child: child);

    child = PermissionScope(
      service: _permissionService,
      controller: _permissionController,
      child: child,
    );

    child = OnboardingScope(
      repository: _onboardingServices.onboardingRepository,
      storage: _onboardingServices.storageRepository,
      photoPicker: _onboardingServices.photoPicker,
      controller: _onboardingServices.controller,
      child: child,
    );

    final settingsServices = widget.settingsServices;
    if (settingsServices != null) {
      child = SettingsScope(services: settingsServices, child: child);
    }

    final supportServices = widget.supportServices;
    if (supportServices != null) {
      child = SupportScope(
        repository: supportServices.repository,
        child: child,
      );
    }

    final social = widget.socialServices;
    if (social != null) {
      child = SocialScope(services: social, child: child);
    }

    final discovery = widget.discoveryRepository;
    if (discovery != null) {
      child = DiscoveryScope(repository: discovery, child: child);
    }

    final music = widget.musicRepository;
    if (music != null) {
      child = MusicScope(repository: music, child: child);
    }

    final humor = widget.humorRepository;
    if (humor != null) {
      child = HumorScope(repository: humor, child: child);
    }

    final relationship = widget.relationshipRepository;
    final profileAnswers = widget.profileQuestionAnswerRepository;
    if (relationship != null && profileAnswers != null) {
      child = RelationshipScope(
        repository: relationship,
        profileAnswers: profileAnswers,
        child: child,
      );
    }

    final learning = widget.relationshipLearningRepository;
    if (learning != null) {
      child = RelationshipLearningScope(
        repository: learning,
        analyticsProvider: widget.analytics,
        journey: _journey,
        child: child,
      );
    }

    final location =
        widget.locationRepository ?? _locationController?.repository;
    final locationController = _locationController;
    if (location != null && locationController != null) {
      child = LocationScope(
        repository: location,
        controller: locationController,
        child: child,
      );
    }

    final purchase = widget.purchaseRepository;
    if (purchase != null) {
      child = BoostScope(
        repository: purchase,
        analytics: widget.analytics,
        child: child,
      );
    }

    final verification = widget.verificationRepository;
    if (verification != null) {
      child = VerificationScope(repository: verification, child: child);
    }

    final subscription = widget.subscriptionServices;
    if (subscription != null) {
      child = SubscriptionScope(
        controller: subscription.controller,
        repository: subscription.repository,
        billing: subscription.billing,
        analytics: widget.analytics,
        child: child,
      );
    }

    final streak = widget.streakServices;
    if (streak != null) {
      child = StreakScope(controller: streak.controller, child: child);
    }

    final operations = widget.appOperations;
    if (operations != null) {
      child = AppOperationsScope(controller: operations, child: child);
    }

    return AppScope(
      config: widget.config,
      logger: widget.logger,
      child: AuthScope(controller: widget.authController, child: child),
    );
  }

  @override
  void dispose() {
    _pushBinder?.dispose();
    widget.authController.removeListener(_syncLocationGate);
    widget.authController.removeListener(_syncLanguageUser);
    widget.authController.removeListener(_syncStreakUser);
    widget.streakServices?.controller.detachLifecycle();
    widget.appOperations?.detachLifecycle();
    widget.authController.removeListener(_syncJourney);
    _journey?.dispose();
    if (_ownsLocationController) {
      _locationController?.dispose();
    }
    if (_ownsLanguageController) {
      _languageController.dispose();
    }
    if (_ownsPermissionController) {
      _permissionController.dispose();
    }
    if (_ownsOnboardingServices) {
      _onboardingServices.controller.dispose();
    }
    _presenceLifecycleController?.dispose();
    _e2eeBootstrapController?.dispose();
    _sessionRecovery?.dispose();
    _router.dispose();
    super.dispose();
  }
}
