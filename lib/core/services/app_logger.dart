import 'dart:developer' as developer;

import 'package:mevora/core/config/app_environment.dart';

class AppLogger {
  const AppLogger({required this.environment});

  final AppEnvironment environment;

  void debug(String message, {Object? error, StackTrace? stackTrace}) {
    if (!environment.isProduction) {
      _log('DEBUG', message, error: error, stackTrace: stackTrace);
    }
  }

  void info(String message) {
    _log('INFO', message);
  }

  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _log('WARN', message, error: error, stackTrace: stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log('ERROR', message, error: error, stackTrace: stackTrace);
  }

  void _log(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'mevora.$level',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
