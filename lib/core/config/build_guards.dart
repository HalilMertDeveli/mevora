import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_environment.dart';

/// Start-up guards that keep a build from running in a state it was never
/// meant to run in. All are pure, so the rules are unit-tested.
///
/// One rule runs through them: what is not known to be development is
/// production. A missing environment, a missing config or a release build
/// never selects a mock, a demo or an emulator.

/// Describes the mismatch between the native build [flavor] and the Dart
/// [environment], or returns null when they agree.
///
/// The Android flavor chooses the native Firebase configuration
/// (`google-services.json`); the Dart entrypoint chooses the environment —
/// Firebase options, App Check provider, analytics, emulator routing. Nothing
/// else ties the two together, and Flutter's default entrypoint
/// (`lib/main.dart`) is the development environment. A production-flavor build
/// started from it would be a store-signed app running development
/// configuration against production native config.
///
/// [flavor] is Flutter's `appFlavor`: null when the build was not given
/// `--flavor` (unit tests, a plain `flutter run`), in which case there is
/// nothing to compare.
String? flavorEnvironmentMismatch({
  required String? flavor,
  required AppEnvironment environment,
}) {
  if (flavor == null || flavor.isEmpty) {
    return null;
  }
  if (flavor == environment.name) {
    return null;
  }
  return 'Build flavor "$flavor" was started from the ${environment.name} '
      'entrypoint. Build it with -t lib/main_$flavor.dart.';
}

/// Whether a `USE_MOCK_*` dart-define may replace a real backend with
/// in-memory fixtures.
///
/// Mocks exist for local UI work only: the [define] must be set, the
/// [environment] must be development, and the build must not be a release
/// build. A missing [environment] counts as production, so a forgotten config
/// can never select a mock.
bool mockDataSourceAllowed({
  required bool define,
  required AppEnvironment? environment,
  bool releaseMode = kReleaseMode,
}) {
  return define && (environment?.isDevelopment ?? false) && !releaseMode;
}

/// Whether demo infrastructure — the in-memory demo deck, the demo matches
/// that go with it and their bundled portraits — may be wired into this build
/// at all.
///
/// Development builds only, and never a release build. It used to be created
/// unconditionally: in production the demo layer sat in front of the real
/// match, chat and safety repositories and kept for itself any conversation
/// whose id happened to contain "mock-".
bool demoInfrastructureAllowed({
  required AppEnvironment? environment,
  bool releaseMode = kReleaseMode,
}) {
  return (environment?.isDevelopment ?? false) && !releaseMode;
}

/// Whether the fixed-price test store may stand in for the real one.
///
/// It has to be asked for, and the build has to be a development one that is
/// not a release build. The store factories used to trust the caller's flag
/// alone.
bool emulatorStoreAllowed({
  required bool requested,
  required AppEnvironment? environment,
  bool releaseMode = kReleaseMode,
}) {
  return requested && (environment?.isDevelopment ?? false) && !releaseMode;
}

/// The development-only `--dart-define`s, and whether each one was passed to
/// this build.
Map<String, bool> developmentDefinesPassed() {
  return const <String, bool>{
    'USE_EMULATORS': bool.fromEnvironment('USE_EMULATORS'),
    'USE_AUTH_EMULATOR': bool.fromEnvironment('USE_AUTH_EMULATOR'),
    'USE_MOCK_DISCOVERY': bool.fromEnvironment('USE_MOCK_DISCOVERY'),
    'USE_MOCK_MUSIC': bool.fromEnvironment('USE_MOCK_MUSIC'),
    'USE_MOCK_RELATIONSHIP': bool.fromEnvironment('USE_MOCK_RELATIONSHIP'),
    'USE_MOCK_HUMOR': String.fromEnvironment('USE_MOCK_HUMOR') == 'true',
    'QA_EMAIL_A': String.fromEnvironment('QA_EMAIL_A') != '',
    'QA_EMAIL_B': String.fromEnvironment('QA_EMAIL_B') != '',
    'QA_PASSWORD': String.fromEnvironment('QA_PASSWORD') != '',
    'DISABLE_PHONE_APP_VERIFICATION': bool.fromEnvironment(
      'DISABLE_PHONE_APP_VERIFICATION',
    ),
    'PHONE_AUTH_TEST_NUMBER':
        String.fromEnvironment('PHONE_AUTH_TEST_NUMBER') != '',
    'PHONE_AUTH_TEST_SMS_CODE':
        String.fromEnvironment('PHONE_AUTH_TEST_SMS_CODE') != '',
    'FIREBASE_APP_CHECK_DEBUG_TOKEN':
        String.fromEnvironment('FIREBASE_APP_CHECK_DEBUG_TOKEN') != '',
  };
}

/// Names the development-only build settings that were passed to a build of
/// another [environment], or returns null when there are none.
///
/// Each of them is already ignored outside development. But a value passed
/// with `--dart-define` is compiled into the binary whether it is used or
/// not: a store build made with a development command line would carry QA
/// credentials and emulator addresses that nothing shows and nobody removed.
/// Refusing to start makes such a build impossible to ship unnoticed.
String? developmentDefinesOutsideDevelopment({
  required AppEnvironment environment,
  required Map<String, bool> passed,
}) {
  if (environment.isDevelopment) {
    return null;
  }
  final leaked = [
    for (final entry in passed.entries)
      if (entry.value) entry.key,
  ]..sort();
  if (leaked.isEmpty) {
    return null;
  }
  return 'Development-only build settings were passed to a '
      '${environment.name} build: ${leaked.join(', ')}. Build it without them.';
}
