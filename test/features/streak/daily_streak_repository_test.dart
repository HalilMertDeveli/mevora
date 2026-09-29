import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/streak/data/callable_daily_streak_repository.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';

class _FakeBackend implements BackendCallable {
  _FakeBackend(this.response);

  final Map<String, dynamic> response;
  String? name;
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    this.name = name;
    this.data = data;
    return response;
  }
}

Map<String, dynamic> _payload([Map<String, dynamic> overrides = const {}]) => {
  'schemaVersion': 1,
  'status': 'continued',
  'credited': true,
  'currentStreak': 8,
  'longestStreak': 12,
  'totalCheckInDays': 34,
  'dayKey': '2026-09-29',
  'newPersonalBest': false,
  'milestone': false,
  ...overrides,
};

void main() {
  group('CallableDailyStreakRepository', () {
    test('calls recordDailyCheckIn with only the offset', () async {
      final backend = _FakeBackend(_payload());
      await CallableDailyStreakRepository(
        backend: backend,
      ).checkIn(timezoneOffsetMinutes: 180);

      expect(backend.name, 'recordDailyCheckIn');
      // No uid, no day and no counters ever leave the device.
      expect(backend.data, {'timezoneOffsetMinutes': 180});
    });

    test('parses a full response', () async {
      final result = await CallableDailyStreakRepository(
        backend: _FakeBackend(_payload({'newPersonalBest': true})),
      ).checkIn(timezoneOffsetMinutes: 0);

      expect(result.status, CheckInStatus.continued);
      expect(result.credited, isTrue);
      expect(result.streak.currentStreak, 8);
      expect(result.streak.longestStreak, 12);
      expect(result.streak.totalCheckInDays, 34);
      expect(result.streak.dayKey, '2026-09-29');
      expect(result.streak.day, DateTime.utc(2026, 9, 29));
      expect(result.newPersonalBest, isTrue);
      expect(result.milestone, isFalse);
    });

    test('parses every status the backend sends', () {
      for (final status in CheckInStatus.values) {
        final result = DailyCheckInResult.fromJson(
          _payload({'status': status.name}),
        );
        expect(result.status, status);
      }
    });

    test('reads a missing credited flag as not credited', () {
      final json = _payload()..remove('credited');
      expect(DailyCheckInResult.fromJson(json).credited, isFalse);
    });

    test('rejects malformed payloads instead of showing a fake zero', () {
      for (final bad in <Map<String, dynamic>>[
        _payload({'status': 'teleported'}),
        _payload({'currentStreak': null}),
        _payload({'currentStreak': '8'}),
        _payload({'longestStreak': -1}),
        _payload({'dayKey': ''}),
        _payload()..remove('totalCheckInDays'),
      ]) {
        expect(
          () => DailyCheckInResult.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });
}
