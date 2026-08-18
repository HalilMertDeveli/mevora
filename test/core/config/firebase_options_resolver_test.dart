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

  test('production Android options target mevora-production', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = FirebaseOptionsResolver.resolve(
      AppEnvironment.production,
    );

    expect(options.projectId, 'mevora-production');
    expect(options.appId, '1:795522345315:android:4c94d1ef039d5eeb89cb56');
  });
}
