import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/firebase/firebase_options_resolver.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/firebase_options.dart';

/// Initializes Firebase products. UI and feature modules must not call
/// Firebase APIs directly.
class FirebaseBootstrap {
  const FirebaseBootstrap({required this.logger});

  final AppLogger logger;

  Future<void> initialize(AppConfig config) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: config.environment.isDevelopment
            ? DefaultFirebaseOptions.currentPlatform
            : FirebaseOptionsResolver.resolve(config.environment),
      );
    }
    // Auth, Firestore, Storage, and Messaging are used only after this.

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    if (config.useEmulators) {
      await _connectEmulators(config);
    } else {
      await _configureLivePhoneAuth();
    }

    await _configureAppCheck(config);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !config.environment.isDevelopment,
    );
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      !config.environment.isDevelopment,
    );
    if (!config.environment.isDevelopment) {
      await FirebaseAnalytics.instance.logAppOpen();
    }
    await FirebaseMessaging.instance.setAutoInitEnabled(true);

    logger.info(
      'Firebase ready (${config.firebaseProjectId}, emulators=${config.useEmulators}, authEmulator=${config.useAuthEmulator})',
    );
  }

  Future<void> _connectEmulators(AppConfig config) async {
    final emulators = config.emulatorConfig;
    if (config.useAuthEmulator) {
      await FirebaseAuth.instance.useAuthEmulator(
        emulators.host,
        emulators.authPort,
      );
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: true,
      );
      logger.info(
        'Auth emulator at ${emulators.host}:${emulators.authPort} (no real SMS)',
      );
    } else {
      await _configureLivePhoneAuth();
      logger.info(
        'Auth uses live ${config.firebaseProjectId} for Phone Auth SMS',
      );
    }
    FirebaseFirestore.instance.useFirestoreEmulator(
      emulators.host,
      emulators.firestorePort,
    );
    await FirebaseStorage.instance.useStorageEmulator(
      emulators.host,
      emulators.storagePort,
    );
    FirebaseFunctions.instance.useFunctionsEmulator(
      emulators.host,
      emulators.functionsPort,
    );
    logger.info(
      'Connected Firestore/Functions/Storage emulators at ${emulators.host}',
    );
  }

  /// Live Phone Auth needs Play Integrity / reCAPTCHA. Never disable
  /// verification against production or staging.
  Future<void> _configureLivePhoneAuth() async {
    try {
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: false,
      );
    } on Object catch (error, stackTrace) {
      logger.warning(
        'Auth phone verification settings were not applied',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _configureAppCheck(AppConfig config) async {
    // Development: skip activation so missing debug tokens / disabled App Check
    // API cannot block Phone Auth. Firebase still may use a placeholder token.
    if (config.environment.isDevelopment) {
      logger.info(
        'App Check skipped in development (non-blocking for Phone Auth)',
      );
      return;
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: config.environment.isProduction
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
        providerApple: config.environment.isProduction
            ? const AppleAppAttestProvider()
            : const AppleDebugProvider(),
      );
    } on Object catch (error, stackTrace) {
      // Non-blocking: Phone Auth and other Firebase calls continue without a
      // valid App Check token when activation fails.
      logger.warning(
        'App Check was not activated; continuing without enforcement',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
