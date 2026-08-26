import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_config.dart';

void main() {
  test('smoke config exposes production project id', () {
    const config = AppConfig(environment: AppEnvironment.production);
    expect(config.firebaseProjectId, 'mevora-production');
    expect(config.packageName, 'com.mevora.app');
  });
}
