import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/firebase/firebase_options_resolver.dart';
import 'package:mevora/core/services/app_logger.dart';

/// Initializes Firebase products. UI and feature modules must not call
/// Firebase APIs directly.
class FirebaseBootstrap {
  const FirebaseBootstrap({required this.logger});

  final AppLogger logger;

  Future<void> initialize(AppConfig config) async {
    final options = FirebaseOptionsResolver.resolve(config.environment);
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }

    if (config.useEmulators) {
      _connectEmulators(config);
    }

    await _configureAppCheck(config);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !config.environment.isDevelopment,
    );
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      !config.environment.isDevelopment,
    );

    logger.info(
      'Firebase ready (${config.firebaseProjectId}, emulators=${config.useEmulators})',
    );
  }

  void _connectEmulators(AppConfig config) {
    final emulators = config.emulatorConfig;
    FirebaseAuth.instance.useAuthEmulator(emulators.host, emulators.authPort);
    FirebaseFirestore.instance.useFirestoreEmulator(
      emulators.host,
      emulators.firestorePort,
    );
    FirebaseStorage.instance.useStorageEmulator(
      emulators.host,
      emulators.storagePort,
    );
    FirebaseFunctions.instance.useFunctionsEmulator(
      emulators.host,
      emulators.functionsPort,
    );
    logger.info('Connected Firebase SDKs to emulators at ${emulators.host}');
  }

  Future<void> _configureAppCheck(AppConfig config) async {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: config.environment.isProduction
            ? AndroidProvider.playIntegrity
            : AndroidProvider.debug,
        appleProvider: config.environment.isProduction
            ? AppleProvider.deviceCheck
            : AppleProvider.debug,
      );
    } on Object catch (error, stackTrace) {
      logger.warning(
        'App Check was not activated',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
