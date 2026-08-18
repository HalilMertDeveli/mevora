import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('development config isolates Firebase to mevora-dev and emulators', () {
    const config = AppConfig(environment: AppEnvironment.development);

    expect(config.appName, 'Mevora Dev');
    expect(config.packageName, 'com.mevora.app.dev');
    expect(config.firebaseProjectId, 'mevora-dev');
    expect(config.useEmulators, isTrue);
    expect(config.showDebugBanner, isTrue);
  });

  test('staging config uses the staging Firebase project', () {
    const config = AppConfig(environment: AppEnvironment.staging);

    expect(config.appName, 'Mevora Staging');
    expect(config.packageName, 'com.mevora.app.staging');
    expect(config.firebaseProjectId, 'mevora-staging');
    expect(config.useEmulators, isFalse);
  });

  test('production config uses the production Firebase project', () {
    const config = AppConfig(environment: AppEnvironment.production);

    expect(config.appName, 'Mevora');
    expect(config.packageName, 'com.mevora.app');
    expect(config.firebaseProjectId, 'mevora-production');
    expect(config.useEmulators, isFalse);
    expect(config.showDebugBanner, isFalse);
    expect(config.enableVerboseLogging, isFalse);
  });

  test('Android emulator host uses the special loopback address', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const config = AppConfig(environment: AppEnvironment.development);

    expect(config.emulatorConfig.host, '10.0.2.2');
    debugDefaultTargetPlatformOverride = null;
  });
}
