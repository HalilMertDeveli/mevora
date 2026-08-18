import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';

class FirebaseAnalyticsAdapter implements AnalyticsProvider {
  FirebaseAnalyticsAdapter({FirebaseAnalytics? analytics})
    : _analytics = analytics ?? FirebaseAnalytics.instance;

  static const _blockedParameterKeys = {
    'email',
    'phone',
    'phoneNumber',
    'password',
    'otp',
    'smsCode',
    'latitude',
    'longitude',
    'gps',
    'token',
    'fcmToken',
    'messageBody',
    'text',
  };

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) {
    return _analytics.logEvent(
      name: name,
      parameters: _withoutPii(parameters),
    );
  }

  @override
  Future<void> setUserId(String? userId) {
    return _analytics.setUserId(id: userId);
  }

  Map<String, Object>? _withoutPii(Map<String, Object>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return parameters;
    }
    final cleaned = <String, Object>{};
    for (final entry in parameters.entries) {
      if (_blockedParameterKeys.contains(entry.key)) {
        continue;
      }
      cleaned[entry.key] = entry.value;
    }
    return cleaned;
  }
}
