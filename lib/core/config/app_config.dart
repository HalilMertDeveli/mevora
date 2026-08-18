import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/firebase/firebase_emulator_config.dart';
import 'package:mevora/core/constants/app_constants.dart';

/// Immutable application configuration resolved at startup.
class AppConfig {
  const AppConfig({required this.environment});

  final AppEnvironment environment;

  String get appName => switch (environment) {
    AppEnvironment.development => '${AppConstants.appName} Dev',
    AppEnvironment.staging => '${AppConstants.appName} Staging',
    AppEnvironment.production => AppConstants.appName,
  };

  String get packageName => switch (environment) {
    AppEnvironment.development => '${AppConstants.packageName}.dev',
    AppEnvironment.staging => '${AppConstants.packageName}.staging',
    AppEnvironment.production => AppConstants.packageName,
  };

  String get firebaseProjectId => switch (environment) {
    AppEnvironment.development => 'mevora-dev',
    AppEnvironment.staging => 'mevora-staging',
    AppEnvironment.production => 'mevora-production',
  };

  bool get showDebugBanner => environment.isDevelopment;

  bool get enableVerboseLogging => !environment.isProduction;

  /// Development talks only to the Emulator Suite.
  bool get useEmulators => environment.isDevelopment;

  FirebaseEmulatorConfig get emulatorConfig {
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    return FirebaseEmulatorConfig(host: host);
  }
}
