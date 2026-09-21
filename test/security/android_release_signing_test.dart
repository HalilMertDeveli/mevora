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

  setUpAll(() {
    gradle = File('android/app/build.gradle.kts').readAsStringSync();
  });

  test('release build type does not hardcode the debug signing config', () {
    expect(
      gradle.contains('signingConfig = signingConfigs.getByName("debug")'),
      isFalse,
      reason: 'the release build type must not be pinned to the debug keystore',
    );
    expect(
      gradle.contains('TODO: Add your own signing config'),
      isFalse,
      reason: 'the Flutter template signing TODO must be resolved',
    );
  });

  test('a release signing config is declared and selected when available', () {
    expect(gradle.contains('signingConfigs.getByName("release")'), isTrue);
    expect(gradle.contains('create("release")'), isTrue);
  });

  test('production release is guarded when signing material is missing', () {
    expect(gradle.contains('assembleProductionRelease'), isTrue);
    expect(gradle.contains('bundleProductionRelease'), isTrue);
    expect(
      gradle.contains('throw GradleException(message)'),
      isTrue,
      reason: 'an unsigned production release must fail the build',
    );
  });

  test('signing material is read from ignored files or the environment', () {
    expect(gradle.contains('key.properties'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEYSTORE_PATH'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEYSTORE_PASSWORD'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEY_ALIAS'), isTrue);
    expect(gradle.contains('MEVORA_ANDROID_KEY_PASSWORD'), isTrue);
  });

  test('no signing secret or keystore path is committed in the build script', () {
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
        reason: 'signing material must never be a literal in the build script',
      );
    }
  });

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
