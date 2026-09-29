import 'package:mevora/features/streak/domain/entities/daily_streak.dart';

/// The daily streak backend. There is deliberately no way to set a streak
/// through this interface — the server owns every counter.
abstract class DailyStreakRepository {
  /// Records today's visit for the signed-in member and returns the result.
  ///
  /// [timezoneOffsetMinutes] only places the member's midnight; the server
  /// decides which day it is from its own clock.
  Future<DailyCheckInResult> checkIn({required int timezoneOffsetMinutes});
}
