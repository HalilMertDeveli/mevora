import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_environment.dart';

/// Start-up guards that keep a build from running in a state it was never
/// meant to run in. Both are pure, so the rules are unit-tested.

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
