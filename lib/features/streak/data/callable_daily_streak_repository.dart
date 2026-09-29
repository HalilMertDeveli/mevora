import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';
import 'package:mevora/features/streak/domain/repositories/daily_streak_repository.dart';

class CallableDailyStreakRepository implements DailyStreakRepository {
  const CallableDailyStreakRepository({required BackendCallable backend})
    : _backend = backend;

  static const String callableName = 'recordDailyCheckIn';

  final BackendCallable _backend;

  @override
  Future<DailyCheckInResult> checkIn({
    required int timezoneOffsetMinutes,
  }) async {
    final payload = await _backend.invoke(callableName, {
      'timezoneOffsetMinutes': timezoneOffsetMinutes,
    });
    return DailyCheckInResult.fromJson(payload);
  }
}
