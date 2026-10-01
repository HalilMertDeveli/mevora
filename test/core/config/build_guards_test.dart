import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/build_guards.dart';

void main() {
  group('flavorEnvironmentMismatch', () {
    test('a build without a flavor is never a mismatch', () {
      for (final environment in AppEnvironment.values) {
        expect(
          flavorEnvironmentMismatch(flavor: null, environment: environment),
          isNull,
        );
        expect(
          flavorEnvironmentMismatch(flavor: '', environment: environment),
          isNull,
        );
      }
    });

    test('a flavor started from its own entrypoint is accepted', () {
      for (final environment in AppEnvironment.values) {
        expect(
          flavorEnvironmentMismatch(
            flavor: environment.name,
            environment: environment,
          ),
          isNull,
        );
      }
    });

    test('the production flavor refuses the development entrypoint', () {
      final mismatch = flavorEnvironmentMismatch(
        flavor: 'production',
        environment: AppEnvironment.development,
      );
      expect(mismatch, isNotNull);
      expect(mismatch, contains('lib/main_production.dart'));
    });

    test('every other flavor and environment pairing is refused', () {
      for (final environment in AppEnvironment.values) {
        for (final flavor in AppEnvironment.values.map((e) => e.name)) {
          if (flavor == environment.name) {
            continue;
          }
          expect(
            flavorEnvironmentMismatch(flavor: flavor, environment: environment),
            isNotNull,
            reason: '$flavor flavor on the ${environment.name} entrypoint',
          );
        }
      }
    });

    test('each Android flavor has a matching Dart entrypoint', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      for (final environment in AppEnvironment.values) {
        expect(gradle, contains('create("${environment.name}")'));
        final entrypoint = File('lib/main_${environment.name}.dart');
        expect(entrypoint.existsSync(), isTrue);
        expect(
          entrypoint.readAsStringSync(),
          contains('bootstrap(AppEnvironment.${environment.name})'),
        );
      }
    });

    test('bootstrap checks the flavor before anything talks to Firebase', () {
      final source = File(
        'lib/bootstrap.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final guard = source.indexOf('flavorEnvironmentMismatch(');
      final firebase = source.indexOf('FirebaseBootstrap(');
      expect(guard, isNonNegative);
      expect(firebase, isNonNegative);
      expect(guard, lessThan(firebase));
    });
  });

  group('mockDataSourceAllowed', () {
    test('needs the define, development and a non-release build', () {
      expect(
        mockDataSourceAllowed(
          define: true,
          environment: AppEnvironment.development,
          releaseMode: false,
        ),
        isTrue,
      );
    });

    test('is off without the define', () {
      expect(
        mockDataSourceAllowed(
          define: false,
          environment: AppEnvironment.development,
          releaseMode: false,
        ),
        isFalse,
      );
    });

    test('staging and production ignore the define', () {
      for (final environment in [
        AppEnvironment.staging,
        AppEnvironment.production,
      ]) {
        expect(
          mockDataSourceAllowed(
            define: true,
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: environment.name,
        );
      }
    });

    test('a release build ignores the define, even in development', () {
      expect(
        mockDataSourceAllowed(
          define: true,
          environment: AppEnvironment.development,
          releaseMode: true,
        ),
        isFalse,
      );
    });

    test('a missing environment counts as production', () {
      expect(
        mockDataSourceAllowed(
          define: true,
          environment: null,
          releaseMode: false,
        ),
        isFalse,
      );
    });

    test('every USE_MOCK_* define in lib/core/di goes through the policy', () {
      final defines = RegExp(r"fromEnvironment\(\s*'USE_MOCK_[A-Z_]+'");
      for (final entity in Directory('lib/core/di').listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final source = entity.readAsStringSync();
        if (!defines.hasMatch(source)) {
          continue;
        }
        expect(
          source.contains('mockDataSourceAllowed(') ||
              source.contains('resolveUseMockHumor('),
          isTrue,
          reason: '${entity.path} honours a USE_MOCK_* define without a gate',
        );
      }
    });
  });
}
