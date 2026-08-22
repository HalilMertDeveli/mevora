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
      await _configureLivePhoneAuth(config);
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
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } else {
      // A second Flutter isolate for FCM + Play Services at launch is enough
      // to trip the emulator low-memory killer (seen at ~460MB RSS).
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    }

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
      await _configureLivePhoneAuth(config);
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

  /// Live Phone Auth needs Play Integrity and/or reCAPTCHA.
  ///
  /// Development disables app verification by default so Console **test
  /// numbers** and debug sideloads work. Play Integrity / reCAPTCHA often
  /// fail or hang on debug builds (empty `taskAffinity` + Custom Tabs).
  ///
  /// - `--dart-define=DISABLE_PHONE_APP_VERIFICATION=false` to exercise real
  ///   verification in development
  /// - `--dart-define=FORCE_PHONE_RECAPTCHA=true` to force the reCAPTCHA path
  ///
  /// Production keeps verification enabled; Firebase picks Play Integrity then
  /// reCAPTCHA.
  Future<void> _configureLivePhoneAuth(AppConfig config) async {
    try {
      const forceRecaptcha = bool.fromEnvironment(
        'FORCE_PHONE_RECAPTCHA',
        defaultValue: false,
      );
      const disableVerificationOverride = bool.fromEnvironment(
        'DISABLE_PHONE_APP_VERIFICATION',
        defaultValue: true,
      );
      final appVerificationDisabled = config.environment.isDevelopment
          ? disableVerificationOverride
          : false;

      // Console test number on mevora-d6ed0 — auto-retrieves OTP in development
      // so first-run smoke tests work without waiting for a carrier SMS.
      // Real numbers still use the normal SMS path.
      const testPhone = String.fromEnvironment(
        'PHONE_AUTH_TEST_NUMBER',
        defaultValue: '+905551112233',
      );
      const testSms = String.fromEnvironment(
        'PHONE_AUTH_TEST_SMS_CODE',
        defaultValue: '123456',
      );

      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: appVerificationDisabled,
        forceRecaptchaFlow: !appVerificationDisabled && forceRecaptcha,
        phoneNumber: config.environment.isDevelopment && testPhone.isNotEmpty
            ? testPhone
            : null,
        smsCode: config.environment.isDevelopment && testSms.isNotEmpty
            ? testSms
            : null,
      );
      logger.info(
        'Live Phone Auth configured '
        '(appVerificationDisabled=$appVerificationDisabled, '
        'forceRecaptchaFlow=${!appVerificationDisabled && forceRecaptcha}, '
        'devTestNumber=${config.environment.isDevelopment && testPhone.isNotEmpty})',
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
    try {
      if (config.environment.isDevelopment) {
        // Debug provider so App Check enforcement (if enabled) does not block
        // Phone Auth / Auth APIs. Register the logged debug token in Console.
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidDebugProvider(),
          providerApple: const AppleDebugProvider(),
        );
        logger.info(
          'App Check debug provider active — register debug token in Console if enforcement is on',
        );
        return;
      }
      await FirebaseAppCheck.instance.activate(
        providerAndroid: config.environment.isProduction
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
        providerApple: config.environment.isProduction
            ? const AppleAppAttestProvider()
            : const AppleDebugProvider(),
      );
    } on Object catch (error, stackTrace) {
      logger.warning(
        'App Check was not activated; continuing without enforcement',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
