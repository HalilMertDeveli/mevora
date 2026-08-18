import 'dart:developer' as developer;

import 'package:mevora/core/config/app_environment.dart';

/// Application logger. Never log passwords, full phone numbers, exact GPS,
/// or auth tokens.
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
      _redact(message),
      name: 'mevora.$level',
      error: error == null ? null : _redact('$error'),
      stackTrace: stackTrace,
    );
  }

  static String _redact(String input) {
    return input
        .replaceAll(RegExp(r'\+[1-9]\d{6,14}'), '[phone]')
        .replaceAll(
          RegExp(
            r'(otp|smsCode|sms_code|idToken|accessToken|refreshToken|purchaseToken|receiptData|signedTransaction|serverVerificationData)\s*[:=]\s*\S+',
            caseSensitive: false,
          ),
          '[redacted]',
        )
        .replaceAll(
          RegExp(
            r'(lat(itude)?|lng|lon(gitude)?)\s*[:=]\s*-?\d+(\.\d+)?',
            caseSensitive: false,
          ),
          '[coord]',
        );
  }
}
