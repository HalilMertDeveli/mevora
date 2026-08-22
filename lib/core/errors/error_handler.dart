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
      if (_isNonFatalPluginNoise(details.exception)) {
        return;
      }
      crashReporter?.recordFlutterFatal(details);
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logger.error(
        'Uncaught platform error',
        error: error,
        stackTrace: stack,
      );
      if (_isNonFatalPluginNoise(error)) {
        return true;
      }
      return crashReporter?.recordUncaught(error, stack) ?? true;
    };
  }

  static bool _isNonFatalPluginNoise(Object error) {
    final message = error.toString();
    return message.contains('Future already completed') ||
        (message.contains('MissingPluginException') &&
            message.contains('firebase_firestore/transaction')) ||
        message.contains('permission-denied') ||
        message.contains('PERMISSION_DENIED') ||
        message.contains("Unsupported scheme 'mock'") ||
        message.contains('Unsupported scheme');
  }
}
