/// What a daily check-in did, as the backend decided it.
enum CheckInStatus {
  /// First streak day ever, or the first after nothing was stored.
  started,

  /// Came back the day after the last streak day.
  continued,

  /// At least one day was skipped; a new streak started at one.
  reset,

  /// Today was already counted. Nothing changed.
  alreadyCounted,

  /// This account is not an active member (mid-onboarding, suspended…).
  ineligible;

  static CheckInStatus? parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }
}

/// The member's streak as last confirmed by the backend. Never computed on
/// the device — the app only displays what the server returned.
class DailyStreak {
  const DailyStreak({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalCheckInDays,
    required this.dayKey,
  });

  final int currentStreak;
  final int longestStreak;
  final int totalCheckInDays;

  /// The member's local day the streak stands on, `YYYY-MM-DD`.
  final String dayKey;

  /// [dayKey] as a UTC date, or null if it is malformed.
  DateTime? get day {
    final parts = dayKey.split('-');
    if (parts.length != 3) {
      return null;
    }
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) {
      return null;
    }
    return DateTime.utc(y, m, d);
  }

  @override
  bool operator ==(Object other) =>
      other is DailyStreak &&
      other.currentStreak == currentStreak &&
      other.longestStreak == longestStreak &&
      other.totalCheckInDays == totalCheckInDays &&
      other.dayKey == dayKey;

  @override
  int get hashCode =>
      Object.hash(currentStreak, longestStreak, totalCheckInDays, dayKey);
}

/// One `recordDailyCheckIn` response.
class DailyCheckInResult {
  const DailyCheckInResult({
    required this.status,
    required this.credited,
    required this.streak,
    this.newPersonalBest = false,
    this.milestone = false,
  });

  /// Parses the callable's payload. Throws [FormatException] on anything that
  /// is not a well-formed response, so a bad payload is a failed refresh —
  /// never a streak of zero shown as if it were real.
  factory DailyCheckInResult.fromJson(Map<String, dynamic> json) {
    final status = CheckInStatus.parse(json['status']);
    if (status == null) {
      throw FormatException('unknown streak status: ${json['status']}');
    }
    int count(String key) {
      final value = json[key];
      if (value is num && value.isFinite && value >= 0) {
        return value.toInt();
      }
      throw FormatException('bad streak field $key: $value');
    }

    final dayKey = json['dayKey'];
    if (dayKey is! String || dayKey.isEmpty) {
      throw FormatException('bad streak dayKey: $dayKey');
    }
    return DailyCheckInResult(
      status: status,
      credited: json['credited'] == true,
      streak: DailyStreak(
        currentStreak: count('currentStreak'),
        longestStreak: count('longestStreak'),
        totalCheckInDays: count('totalCheckInDays'),
        dayKey: dayKey,
      ),
      newPersonalBest: json['newPersonalBest'] == true,
      milestone: json['milestone'] == true,
    );
  }

  final CheckInStatus status;

  /// True only when this very call added a new day. The celebration keys off
  /// this and nothing else.
  final bool credited;
  final DailyStreak streak;
  final bool newPersonalBest;
  final bool milestone;
}
