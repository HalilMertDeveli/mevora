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

  /// Live Phone Auth needs Play Integrity and/or reCAPTCHA for **real SMS**.
  ///
  /// Defaults target carrier SMS (not Console test numbers):
  /// - App verification is **enabled** (required for real phone numbers).
  /// - Play Integrity is preferred (SHA-1 + SHA-256 must be in Firebase Console).
  /// - reCAPTCHA is **not** forced by default — forcing it without a hostable
  ///   Activity caused `FirebaseAuthMissingActivityForRecaptchaException` and
  ///   blocked real SMS. Opt in with `--dart-define=FORCE_PHONE_RECAPTCHA=true`.
  ///
  /// Console test numbers (no carrier SMS) — opt in explicitly:
  /// `--dart-define=DISABLE_PHONE_APP_VERIFICATION=true`
  /// `--dart-define=PHONE_AUTH_TEST_NUMBER=+905551112233`
  /// `--dart-define=PHONE_AUTH_TEST_SMS_CODE=123456`
  Future<void> _configureLivePhoneAuth(AppConfig config) async {
    try {
      const disableVerification = bool.fromEnvironment(
        'DISABLE_PHONE_APP_VERIFICATION',
        defaultValue: false,
      );
      // Empty by default — never inject a Console test pair into production SMS.
      const testPhone = String.fromEnvironment(
        'PHONE_AUTH_TEST_NUMBER',
        defaultValue: '',
      );
      const testSms = String.fromEnvironment(
        'PHONE_AUTH_TEST_SMS_CODE',
        defaultValue: '',
      );

      final appVerificationDisabled =
          config.environment.isDevelopment && disableVerification;
      // Only force reCAPTCHA when explicitly requested. Default: Play Integrity.
      final forceRecaptcha = !appVerificationDisabled &&
          const bool.fromEnvironment('FORCE_PHONE_RECAPTCHA', defaultValue: false);
      final useDevTestPair = config.environment.isDevelopment &&
          appVerificationDisabled &&
          testPhone.isNotEmpty &&
          testSms.isNotEmpty;

      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: appVerificationDisabled,
        forceRecaptchaFlow: forceRecaptcha,
        phoneNumber: useDevTestPair ? testPhone : null,
        smsCode: useDevTestPair ? testSms : null,
      );
      // ignore: avoid_print
      print(
        '[PHONE_AUTH] SETTINGS '
        'appVerificationDisabled=$appVerificationDisabled '
        'forceRecaptchaFlow=$forceRecaptcha '
        'devTestNumber=$useDevTestPair '
        'project=${config.firebaseProjectId}',
      );
      logger.info(
        'Live Phone Auth configured '
        '(appVerificationDisabled=$appVerificationDisabled, '
        'forceRecaptchaFlow=$forceRecaptcha, '
        'devTestNumber=$useDevTestPair)',
      );
    } on Object catch (error, stackTrace) {
      // ignore: avoid_print
      print('[PHONE_AUTH] SETTINGS_FAILED error=$error');
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
        // Prefer --dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN (flutter_run_dev /
        // launch.json). Fallback matches tool/app_check_debug_token.local so plain
        // `flutter run` still passes App Check in development.
        const fromEnv = String.fromEnvironment(
          'FIREBASE_APP_CHECK_DEBUG_TOKEN',
        );
        const registeredDevFallback =
            '18424c44-83a0-47d2-b57d-dd71ef21ca73';
        final debugToken =
            fromEnv.isNotEmpty ? fromEnv : registeredDevFallback;
        await FirebaseAppCheck.instance.activate(
          providerAndroid: AndroidDebugProvider(debugToken: debugToken),
          providerApple: AppleDebugProvider(debugToken: debugToken),
        );
        // ignore: avoid_print
        print(
          '[APPCHECK_DEBUG] activated development '
          'hasFixedToken=true fromEnv=${fromEnv.isNotEmpty}',
        );
        if (fromEnv.isEmpty) {
          logger.info(
            'App Check using registered development debug-token fallback',
          );
        } else {
          logger.info('App Check debug provider active with dart-define token');
        }
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
