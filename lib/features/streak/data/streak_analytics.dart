import 'dart:async';

import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';

/// Daily streak product events.
///
/// Only credited days are logged — a same-day reopen produces no event — and
/// parameters are coarse: a length bucket, never a uid, day or timestamp.
class StreakAnalytics {
  const StreakAnalytics(this._analytics);

  final AnalyticsProvider? _analytics;

  static String lengthBucket(int days) {
    if (days <= 1) return '1';
    if (days <= 3) return '2_3';
    if (days <= 7) return '4_7';
    if (days <= 14) return '8_14';
    if (days <= 30) return '15_30';
    if (days <= 100) return '31_100';
    return '100_plus';
  }

  Future<void> _log(String name, Map<String, Object> params) async {
    final analytics = _analytics;
    if (analytics == null) {
      return;
    }
    try {
      await analytics.logEvent(name, parameters: params);
    } on Object {
      // Measurement never breaks the experience it measures.
    }
  }

  /// A new day was credited.
  void checkIn(DailyCheckInResult result) {
    if (!result.credited) {
      return;
    }
    final bucket = lengthBucket(result.streak.currentStreak);
    unawaited(
      _log(AnalyticsEvents.streakCheckIn, {
        'status': result.status.name,
        'streak_length_bucket': bucket,
        'personal_best': result.newPersonalBest ? 1 : 0,
      }),
    );
    if (result.newPersonalBest) {
      unawaited(
        _log(AnalyticsEvents.streakPersonalBest, {
          'streak_length_bucket': bucket,
        }),
      );
    }
  }

  void detailsViewed(DailyStreak streak) {
    unawaited(
      _log(AnalyticsEvents.streakDetailsViewed, {
        'streak_length_bucket': lengthBucket(streak.currentStreak),
      }),
    );
  }
}
