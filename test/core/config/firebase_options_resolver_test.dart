import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/firebase/firebase_options_resolver.dart';
import 'package:mevora/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('development Android options target mevora-d6ed0', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = FirebaseOptionsResolver.resolve(
      AppEnvironment.development,
    );

    expect(options.projectId, 'mevora-d6ed0');
    expect(options, DefaultFirebaseOptions.android);
    expect(options.appId, '1:821220262229:android:1a12a39a06a7516f702fdc');
    expect(options.messagingSenderId, '821220262229');
  });

  test('development iOS options use com.mevora.app on mevora-d6ed0', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final options = FirebaseOptionsResolver.resolve(
      AppEnvironment.development,
    );

    expect(options.projectId, 'mevora-d6ed0');
    expect(options, DefaultFirebaseOptions.ios);
    expect(options.iosBundleId, 'com.mevora.app');
    expect(options.appId, '1:821220262229:ios:634b8b3284cc59fc702fdc');
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
