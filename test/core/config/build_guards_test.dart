import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/build_guards.dart';

void main() {
  group('developmentDefinesOutsideDevelopment', () {
    const none = <String, bool>{
      'USE_EMULATORS': false,
      'QA_EMAIL_A': false,
      'QA_PASSWORD': false,
    };

    test('a development build may be given any of them', () {
      expect(
        developmentDefinesOutsideDevelopment(
          environment: AppEnvironment.development,
          passed: const {'USE_EMULATORS': true, 'QA_PASSWORD': true},
        ),
        isNull,
      );
    });

    test('a staging or production build given none of them starts', () {
      for (final environment in [
        AppEnvironment.staging,
        AppEnvironment.production,
      ]) {
        expect(
          developmentDefinesOutsideDevelopment(
            environment: environment,
            passed: none,
          ),
          isNull,
        );
      }
    });

    test('a staging or production build given one of them is refused, and '
        'the message names it', () {
      for (final environment in [
        AppEnvironment.staging,
        AppEnvironment.production,
      ]) {
        final message = developmentDefinesOutsideDevelopment(
          environment: environment,
          passed: const {
            'USE_EMULATORS': false,
            'QA_PASSWORD': true,
            'QA_EMAIL_A': true,
          },
        );
        expect(message, isNotNull);
        expect(message, contains(environment.name));
        expect(message, contains('QA_EMAIL_A, QA_PASSWORD'));
        expect(message, isNot(contains('USE_EMULATORS')));
      }
    });

    test('the message never carries a value, only names', () {
      // The values are credentials; the keys are enough to fix the build.
      final message = developmentDefinesOutsideDevelopment(
        environment: AppEnvironment.production,
        passed: const {'QA_PASSWORD': true},
      );
      expect(message, isNot(contains('=')));
    });

    test('a plain test run passes none of them', () {
      // flutter test is given no --dart-define, which is the shape of a
      // store build. If one of these ever gained a default, this fails.
      expect(developmentDefinesPassed().values, everyElement(isFalse));
    });

    test('every development-only define the app reads is on the list', () {
      // A define read somewhere in lib/ but missing here could be passed to
      // a production build without anything noticing.
      final listed = developmentDefinesPassed().keys.toSet();
      final developmentOnly = RegExp(
        r"fromEnvironment\(\s*'((?:USE_MOCK_|USE_EMULATORS|USE_AUTH_EMULATOR|"
        r'QA_|PHONE_AUTH_TEST_|DISABLE_PHONE_APP_VERIFICATION|'
        r"FIREBASE_APP_CHECK_DEBUG_TOKEN)[A-Z_]*)'",
      );
      final read = <String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        for (final match in developmentOnly.allMatches(
          entity.readAsStringSync(),
        )) {
          read.add(match.group(1)!);
        }
      }
      expect(read, isNotEmpty);
      expect(read.difference(listed), isEmpty);
    });
  });

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

    test('demo infrastructure exists in a debug development build only', () {
      expect(
        demoInfrastructureAllowed(
          environment: AppEnvironment.development,
          releaseMode: false,
        ),
        isTrue,
      );
      expect(
        demoInfrastructureAllowed(
          environment: AppEnvironment.development,
          releaseMode: true,
        ),
        isFalse,
      );
      for (final environment in <AppEnvironment?>[
        AppEnvironment.staging,
        AppEnvironment.production,
        // Not knowing the environment is not a reason to show a demo.
        null,
      ]) {
        expect(
          demoInfrastructureAllowed(
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: '$environment',
        );
      }
    });

    test('the app builds its demo hub and demo portraits behind that rule', () {
      final source = File('lib/bootstrap.dart').readAsStringSync();
      expect(
        source,
        contains('demoInfrastructureAllowed(environment: environment)'),
      );
      expect(
        RegExp(r'DemoSocialHub\(').allMatches(source),
        hasLength(1),
        reason: 'one construction, and it is the guarded one',
      );
      expect(
        source,
        contains('demoAllowed ? DemoSocialHub(uidSource: uidSource) : null'),
      );
      expect(
        source,
        contains('MevoraPhotoImages.demoPortraitsAvailable = demoAllowed'),
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
