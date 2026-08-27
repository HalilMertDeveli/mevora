class MatchingStreak {
  const MatchingStreak({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastParticipatedDay,
    required this.dailyParticipation,
    required this.unlockedRewardIds,
  });

  static const MatchingStreak empty = MatchingStreak(
    currentStreak: 0,
    longestStreak: 0,
    lastParticipatedDay: null,
    dailyParticipation: false,
    unlockedRewardIds: [],
  );

  final int currentStreak;
  final int longestStreak;
  final String? lastParticipatedDay;
  final bool dailyParticipation;
  final List<String> unlockedRewardIds;
}
