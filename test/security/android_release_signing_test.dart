import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract for `android/app/build.gradle.kts`.
///
/// A store build signed with the debug keystore is rejected by Google Play and
/// breaks Google Sign-In, Spotify OAuth and App Check, all of which are pinned
/// to the release certificate fingerprint. These assertions keep the release
/// configuration from silently regressing to the Flutter template default.
void main() {
  late String gradle;

  /// The body of one `create("<flavor>") { ... }` block.
  String flavorBlock(String flavor) {
    final start = gradle.indexOf('create("$flavor") {');
    expect(start, isNonNegative, reason: 'flavor $flavor must exist');
    final end = gradle.indexOf('}', start);
    return gradle.substring(start, end);
  }

  setUpAll(() {
    gradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('the release build type sets no signing config of its own', () {
    // A build-type signing config overrides the flavor's. With one set here,
    // every flavor's release would be signed with the same key.
    final start = gradle.indexOf('buildTypes {');
    expect(start, isNonNegative);
    final buildTypes = gradle.substring(start, gradle.indexOf('\n}\n', start));
    expect(buildTypes, contains('signingConfig = null'));
    expect(buildTypes, isNot(contains('signingConfigs.getByName')));
    expect(
      gradle.contains('TODO: Add your own signing config'),
      isFalse,
      reason: 'the Flutter template signing TODO must be resolved',
    );
  });

  test('only the production flavor is signed with the release keystore', () {
    expect(gradle, contains('create("release")'));
    expect(
      gradle,
      contains('val debugKeystore = signingConfigs.getByName("debug")'),
    );
    expect(gradle, contains('signingConfigs.getByName("release")'));

    expect(
      flavorBlock('production'),
      contains('signingConfig = productionKeystore'),
    );
    // Development shares the production applicationId: release-signed, it
    // would be an uploadable store artifact wired to the development backend.
    expect(
      flavorBlock('development'),
      contains('signingConfig = debugKeystore'),
    );
    expect(flavorBlock('staging'), contains('signingConfig = debugKeystore'));
  });

  test('production release is guarded when signing material is missing', () {
    expect(gradle.contains('assembleProductionRelease'), isTrue);
    expect(gradle.contains('bundleProductionRelease'), isTrue);
    expect(gradle.contains('packageProductionRelease'), isTrue);
    expect(
      gradle.contains('throw GradleException(message)'),
      isTrue,
      reason: 'an unsigned production release must fail the build',
    );
    expect(gradle, contains('if (releaseSigning == null) {'));
    expect(
      gradle,
      contains(
        'Refusing to sign a production release with the debug keystore.',
      ),
    );
  });

  test('production release is guarded against a non-production entrypoint', () {
    // The default Flutter entrypoint is the development environment. A
    // production bundle built without `-t lib/main_production.dart` would ship
    // development Firebase options and the App Check debug provider.
    expect(
      gradle,
      contains('val productionEntrypoint = "lib/main_production.dart"'),
    );
    expect(gradle, contains('project.findProperty("target")'));
    expect(
      gradle,
      contains('if (!flutterTarget.endsWith(productionEntrypoint)) {'),
    );
    expect(File('lib/main_production.dart').existsSync(), isTrue);
    expect(
      File('lib/main_production.dart').readAsStringSync(),
      contains('bootstrap(AppEnvironment.production)'),
    );
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('bootstrap(AppEnvironment.development)'),
      reason: 'the guard exists because the default entrypoint is development',
    );
  });

  test('signing material is read from ignored files or the environment', () {
    expect(gradle.contains('key.properties'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEYSTORE_PATH'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEYSTORE_PASSWORD'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEY_ALIAS'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEY_PASSWORD'), isTrue);
  });

  test(
    'no signing secret or keystore path is committed in the build script',
    () {
      // Any literal assignment of a password/alias would be a committed secret.
      for (final pattern in [
        RegExp(r'storePassword\s*=\s*"[^"$]+"'),
        RegExp(r'keyPassword\s*=\s*"[^"$]+"'),
        RegExp(r'keyAlias\s*=\s*"[^"$]+"'),
        RegExp(r'storeFile\s*=\s*file\("[^"$]+"\)'),
      ]) {
        expect(
          pattern.hasMatch(gradle),
          isFalse,
          reason:
              'signing material must never be a literal in the build script',
        );
      }
    },
  );

  test('keystores and key.properties stay git-ignored', () {
    final androidIgnore = File('android/.gitignore').readAsStringSync();
    final rootIgnore = File('.gitignore').readAsStringSync();
    expect(androidIgnore.contains('key.properties'), isTrue);
    expect(androidIgnore.contains('*.jks'), isTrue);
    expect(androidIgnore.contains('*.keystore'), isTrue);
    expect(rootIgnore.contains('key.properties'), isTrue);
    expect(rootIgnore.contains('*.jks'), isTrue);
    expect(rootIgnore.contains('*.keystore'), isTrue);
  });

  test('no keystore is tracked anywhere in the repository', () {
    final tracked = Process.runSync('git', [
      'ls-files',
      '*.jks',
      '*.keystore',
      '*.p12',
      'key.properties',
    ]);
    expect(
      (tracked.stdout as String).trim(),
      isEmpty,
      reason: 'signing material must never be committed',
    );
  });
}
