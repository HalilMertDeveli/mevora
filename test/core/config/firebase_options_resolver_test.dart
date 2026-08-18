import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/firebase/firebase_options_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('development Android options target mevora-dev', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = FirebaseOptionsResolver.resolve(
      AppEnvironment.development,
    );

    expect(options.projectId, 'mevora-dev');
    expect(options.appId, '1:462386294396:android:aff3c8aa15f4041ac963f9');
    expect(options.messagingSenderId, '462386294396');
    expect(options.androidClientId, isNull);
  });

  test('development iOS options use the .dev bundle id', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final options = FirebaseOptionsResolver.resolve(
      AppEnvironment.development,
    );

    expect(options.projectId, 'mevora-dev');
    expect(options.iosBundleId, 'com.mevora.app.dev');
    expect(options.appId, '1:462386294396:ios:233c5fa39e0ca788c963f9');
  });

  test('staging Android options target mevora-staging', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = FirebaseOptionsResolver.resolve(AppEnvironment.staging);

    expect(options.projectId, 'mevora-staging');
    expect(options.appId, '1:905717896949:android:6d0fce4d2c911c2fbc57bc');
    expect(options.messagingSenderId, '905717896949');
  });

  test('staging iOS options use the .staging bundle id', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final options = FirebaseOptionsResolver.resolve(AppEnvironment.staging);

    expect(options.projectId, 'mevora-staging');
    expect(options.iosBundleId, 'com.mevora.app.staging');
    expect(options.appId, '1:905717896949:ios:7ae531c8688973c9bc57bc');
  });

  test('production Android options target mevora-production', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = FirebaseOptionsResolver.resolve(
      AppEnvironment.production,
    );

    expect(options.projectId, 'mevora-production');
    expect(options.appId, '1:795522345315:android:4c94d1ef039d5eeb89cb56');
  });

  test('production iOS options use the store bundle id', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final options = FirebaseOptionsResolver.resolve(
      AppEnvironment.production,
    );

    expect(options.projectId, 'mevora-production');
    expect(options.iosBundleId, 'com.mevora.app');
    expect(options.appId, '1:795522345315:ios:e61a29297d81eedb89cb56');
  });
}
