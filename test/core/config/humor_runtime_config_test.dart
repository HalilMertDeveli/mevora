import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/humor_runtime_config.dart';

void main() {
  group('resolveUseMockHumor', () {
    test('forced true always mocks', () {
      expect(
        resolveUseMockHumor(
          AppEnvironment.production,
          debugMode: false,
          forcedMockHumor: 'true',
        ),
        isTrue,
      );
    });

    test('forced false always uses real backend', () {
      expect(
        resolveUseMockHumor(
          AppEnvironment.development,
          debugMode: true,
          forcedMockHumor: 'false',
        ),
        isFalse,
      );
    });

    test('debug development defaults to mock', () {
      expect(
        resolveUseMockHumor(
          AppEnvironment.development,
          debugMode: true,
          forcedMockHumor: '',
        ),
        isTrue,
      );
    });

    test('production release defaults to real backend', () {
      expect(
        resolveUseMockHumor(
          AppEnvironment.production,
          debugMode: false,
          forcedMockHumor: '',
        ),
        isFalse,
      );
    });

    test('staging release defaults to real backend', () {
      expect(
        resolveUseMockHumor(
          AppEnvironment.staging,
          debugMode: false,
          forcedMockHumor: '',
        ),
        isFalse,
      );
    });
  });

  group('resolveHumorLabEnabled', () {
    test('forced true enables everywhere', () {
      expect(
        resolveHumorLabEnabled(
          AppEnvironment.production,
          debugMode: false,
          forcedHumorLab: 'true',
        ),
        isTrue,
      );
    });

    test('forced false disables everywhere', () {
      expect(
        resolveHumorLabEnabled(
          AppEnvironment.development,
          debugMode: true,
          forcedHumorLab: 'false',
        ),
        isFalse,
      );
    });

    test('debug development enables Humor Lab', () {
      expect(
        resolveHumorLabEnabled(
          AppEnvironment.development,
          debugMode: true,
          forcedHumorLab: '',
        ),
        isTrue,
      );
    });

    test('staging enables Humor Lab for QA', () {
      expect(
        resolveHumorLabEnabled(
          AppEnvironment.staging,
          debugMode: false,
          forcedHumorLab: '',
        ),
        isTrue,
      );
    });

    test('production release stays off until Remote Config', () {
      expect(
        resolveHumorLabEnabled(
          AppEnvironment.production,
          debugMode: false,
          forcedHumorLab: '',
        ),
        isFalse,
      );
    });
  });
}
