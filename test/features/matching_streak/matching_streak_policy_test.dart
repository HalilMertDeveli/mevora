import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/matching_streak/domain/services/matching_streak_policy.dart';

void main() {
  group('MatchingStreakPolicy', () {
    test('istanbulDayKey uses UTC+3 day boundary', () {
      final lateUtc = DateTime.utc(2026, 8, 26, 22, 30);
      expect(MatchingStreakPolicy.istanbulDayKey(lateUtc), '2026-08-27');
      final earlyUtc = DateTime.utc(2026, 8, 26, 20, 30);
      expect(MatchingStreakPolicy.istanbulDayKey(earlyUtc), '2026-08-26');
    });

    test('same day participation flag', () {
      expect(
        MatchingStreakPolicy.dailyParticipation(
          lastParticipatedDay: '2026-08-27',
          todayKey: '2026-08-27',
        ),
        isTrue,
      );
      expect(
        MatchingStreakPolicy.dailyParticipation(
          lastParticipatedDay: '2026-08-26',
          todayKey: '2026-08-27',
        ),
        isFalse,
      );
    });

    test('effective streak survives overnight until a miss', () {
      expect(
        MatchingStreakPolicy.effectiveStreak(
          storedStreak: 7,
          lastParticipatedDay: '2026-08-26',
          todayKey: '2026-08-27',
        ),
        7,
      );
      expect(
        MatchingStreakPolicy.effectiveStreak(
          storedStreak: 7,
          lastParticipatedDay: '2026-08-25',
          todayKey: '2026-08-27',
        ),
        0,
      );
    });

    test('previous day crosses month boundary', () {
      expect(
        MatchingStreakPolicy.previousIstanbulDayKey('2026-09-01'),
        '2026-08-31',
      );
    });
  });
}
