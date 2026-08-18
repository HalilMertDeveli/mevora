import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/config/firebase/firebase_emulator_config.dart';
import 'package:mevora/core/constants/app_constants.dart';

/// Immutable application configuration resolved at startup.
class AppConfig {
  const AppConfig({
    required this.environment,
    this.featureFlags = const FeatureFlags(),
  });

  final AppEnvironment environment;
  final FeatureFlags featureFlags;

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

  /// Development talks to the Emulator Suite for Firestore, Functions, and
  /// Storage. Pass `--dart-define=USE_EMULATORS=false` on a physical device
  /// so the whole stack uses live `mevora-dev` (10.0.2.2 is unreachable there).
  bool get useEmulators {
    if (!environment.isDevelopment) {
      return false;
    }
    return const bool.fromEnvironment('USE_EMULATORS', defaultValue: true);
  }

  /// Auth emulator never sends SMS. Off by default so Phone Auth uses live
  /// `mevora-dev`. Opt in with `--dart-define=USE_AUTH_EMULATOR=true` for
  /// local test numbers only.
  bool get useAuthEmulator {
    if (!useEmulators) {
      return false;
    }
    return const bool.fromEnvironment(
      'USE_AUTH_EMULATOR',
      defaultValue: false,
    );
  }

  FirebaseEmulatorConfig get emulatorConfig {
    const fromEnv = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
    final host = fromEnv.isNotEmpty
        ? fromEnv
        : defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    return FirebaseEmulatorConfig(host: host);
  }

  /// Public Spotify OAuth client ID. The client secret never ships in the app.
  String get spotifyClientId =>
      const String.fromEnvironment('SPOTIFY_CLIENT_ID');

  String get spotifyRedirectUri => const String.fromEnvironment(
    'SPOTIFY_REDIRECT_URI',
    defaultValue: 'mevora://auth/spotify',
  );

  /// Web OAuth client ID used by Google Sign-In on Android (id token).
  String get googleWebClientId =>
      const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Apple Services ID used for Sign in with Apple on Android.
  String get appleServiceId => const String.fromEnvironment(
    'APPLE_SERVICE_ID',
    defaultValue: 'com.mevora.app.service',
  );

  String get appleRedirectUri {
    const fromEnv = String.fromEnvironment('APPLE_REDIRECT_URI');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return 'https://$firebaseProjectId.firebaseapp.com/__/auth/handler';
  }

  String get termsOfServiceUrl => const String.fromEnvironment(
    'TERMS_URL',
    defaultValue: 'https://mevora.app/terms',
  );

  String get privacyPolicyUrl => const String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: 'https://mevora.app/privacy',
  );

  String get functionsRegion => const String.fromEnvironment(
    'FUNCTIONS_REGION',
    defaultValue: 'europe-west1',
  );
}
