import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/constants/app_constants.dart';

void main() {
  test('development config exposes a debug-friendly app name', () {
    const config = AppConfig(environment: AppEnvironment.development);

    expect(config.appName, 'Mevora Dev');
    expect(config.packageName, AppConstants.packageName);
    expect(config.showDebugBanner, isTrue);
    expect(config.enableVerboseLogging, isTrue);
  });

  test('production config uses the public app name', () {
    const config = AppConfig(environment: AppEnvironment.production);

    expect(config.appName, AppConstants.appName);
    expect(config.showDebugBanner, isFalse);
    expect(config.enableVerboseLogging, isFalse);
  });
}
