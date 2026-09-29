import 'dart:async';
import 'dart:collection';

import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';
import 'package:mevora/features/streak/domain/repositories/daily_streak_repository.dart';

DailyCheckInResult streakResult({
  CheckInStatus status = CheckInStatus.continued,
  bool? credited,
  int current = 8,
  int longest = 12,
  int total = 34,
  String dayKey = '2026-09-29',
  bool newPersonalBest = false,
  bool milestone = false,
}) {
  return DailyCheckInResult(
    status: status,
    credited:
        credited ??
        (status != CheckInStatus.alreadyCounted &&
            status != CheckInStatus.ineligible),
    streak: DailyStreak(
      currentStreak: current,
      longestStreak: longest,
      totalCheckInDays: total,
      dayKey: dayKey,
    ),
    newPersonalBest: newPersonalBest,
    milestone: milestone,
  );
}

/// Serves scripted results (or errors) in order; repeats the last one once
/// the script runs out. [gate], when set, holds every call until completed.
class ScriptedStreakRepository implements DailyStreakRepository {
  ScriptedStreakRepository([Iterable<Object> script = const []])
    : _script = Queue.of(script);

  final Queue<Object> _script;
  Object? _last;
  final List<int> offsets = <int>[];
  Completer<void>? gate;

  int get calls => offsets.length;

  void enqueue(Object next) => _script.add(next);

  @override
  Future<DailyCheckInResult> checkIn({
    required int timezoneOffsetMinutes,
  }) async {
    offsets.add(timezoneOffsetMinutes);
    final next = _script.isNotEmpty ? _script.removeFirst() : _last;
    _last = next;
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    if (next is DailyCheckInResult) {
      return next;
    }
    if (next == null) {
      throw StateError('no scripted streak result');
    }
    throw next;
  }
}

class RecordingAnalytics implements AnalyticsProvider {
  final List<String> events = <String>[];
  final List<Map<String, Object>?> parameters = <Map<String, Object>?>[];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add(name);
    this.parameters.add(parameters);
  }

  @override
  Future<void> setUserId(String? userId) async {}
}
