import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/firebase_options.dart';

/// Firebase options for each Mevora environment and platform.
///
/// Development / default init uses generated `lib/firebase_options.dart`
/// (`mevora-d6ed0`). Staging and production keep their existing projects.
/// Native files must stay aligned with:
/// - `android/app/google-services.json` (and `android/app/src/{flavor}/`)
/// - `ios/Runner/GoogleService-Info.plist` (and `ios/flavors/{flavor}/`)
abstract final class FirebaseOptionsResolver {
  static FirebaseOptions resolve(AppEnvironment environment) {
    return switch (environment) {
      AppEnvironment.development => _development,
      AppEnvironment.staging => _staging,
      AppEnvironment.production => _production,
    };
  }

  /// Sourced from [DefaultFirebaseOptions] so development points at mevora-d6ed0.
  static FirebaseOptions get _development {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => DefaultFirebaseOptions.android,
      TargetPlatform.iOS => DefaultFirebaseOptions.ios,
      _ => DefaultFirebaseOptions.android,
    };
  }

  static FirebaseOptions get _staging {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidStaging,
      TargetPlatform.iOS => _iosStaging,
      _ => _androidStaging,
    };
  }

  static FirebaseOptions get _production {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidProduction,
      TargetPlatform.iOS => _iosProduction,
      _ => _androidProduction,
    };
  }

  static const FirebaseOptions _androidStaging = FirebaseOptions(
    apiKey: 'AIzaSyC7dWuaKZmX1c5q4QyQPLUKBPhRvNSqaW0',
    appId: '1:905717896949:android:6d0fce4d2c911c2fbc57bc',
    messagingSenderId: '905717896949',
    projectId: 'mevora-staging',
    storageBucket: 'mevora-staging.firebasestorage.app',
  );

  static const FirebaseOptions _iosStaging = FirebaseOptions(
    apiKey: 'AIzaSyDUeAPOus2aU7Pc3YEtZTHfve3nyI3V1ig',
    appId: '1:905717896949:ios:7ae531c8688973c9bc57bc',
    messagingSenderId: '905717896949',
    projectId: 'mevora-staging',
    storageBucket: 'mevora-staging.firebasestorage.app',
    iosBundleId: 'com.mevora.app.staging',
  );

  static const FirebaseOptions _androidProduction = FirebaseOptions(
    apiKey: 'AIzaSyCmzqA726MdPHumO8Otb1rP4KkfF_BwhIE',
    appId: '1:795522345315:android:4c94d1ef039d5eeb89cb56',
    messagingSenderId: '795522345315',
    projectId: 'mevora-production',
    storageBucket: 'mevora-production.firebasestorage.app',
  );

  static const FirebaseOptions _iosProduction = FirebaseOptions(
    apiKey: 'AIzaSyDC5bSc6PaC_sCkbCnXbGpx8efKIUo9DkY',
    appId: '1:795522345315:ios:e61a29297d81eedb89cb56',
    messagingSenderId: '795522345315',
    projectId: 'mevora-production',
    storageBucket: 'mevora-production.firebasestorage.app',
    iosBundleId: 'com.mevora.app',
  );
}
