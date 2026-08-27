/// Client-side Istanbul day helpers (Turkey is permanently UTC+3).
abstract final class MatchingStreakPolicy {
  static const Duration istanbulOffset = Duration(hours: 3);

  static DateTime istanbulNow([DateTime? utcOrLocal]) {
    final utc = (utcOrLocal ?? DateTime.now()).toUtc();
    return utc.add(istanbulOffset);
  }

  static String istanbulDayKey([DateTime? now]) {
    final i = istanbulNow(now);
    final y = i.year.toString().padLeft(4, '0');
    final m = i.month.toString().padLeft(2, '0');
    final d = i.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String previousIstanbulDayKey(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) {
      throw ArgumentError.value(dayKey, 'dayKey');
    }
    final noonUtc = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
      9,
    );
    return istanbulDayKey(noonUtc.subtract(const Duration(days: 1)));
  }

  static int effectiveStreak({
    required int storedStreak,
    required String? lastParticipatedDay,
    String? todayKey,
  }) {
    if (storedStreak <= 0 || lastParticipatedDay == null) return 0;
    final today = todayKey ?? istanbulDayKey();
    if (lastParticipatedDay == today) return storedStreak;
    if (lastParticipatedDay == previousIstanbulDayKey(today)) {
      return storedStreak;
    }
    return 0;
  }

  static bool dailyParticipation({
    required String? lastParticipatedDay,
    String? todayKey,
  }) {
    return lastParticipatedDay == (todayKey ?? istanbulDayKey());
  }
}
