import 'package:flutter/foundation.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/crash_reporter.dart';

/// Registers global Flutter error hooks. UI fallbacks are configured in
/// bootstrap so this layer stays free of widgets.
abstract final class ErrorHandler {
  static void register({
    required AppLogger logger,
    CrashReporter? crashReporter,
  }) {
    FlutterError.onError = (details) {
      logger.error(
        'Flutter framework error',
        error: details.exception,
        stackTrace: details.stack,
      );
      crashReporter?.recordFlutterFatal(details);
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logger.error(
        'Uncaught platform error',
        error: error,
        stackTrace: stack,
      );
      return crashReporter?.recordUncaught(error, stack) ?? true;
    };
  }
}
