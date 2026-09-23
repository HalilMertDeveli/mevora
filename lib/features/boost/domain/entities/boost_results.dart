/// What a Boost period actually delivered.
///
/// Server-written and owner-read only. Every number is the backend's own
/// count; the client never reports being viewed and never writes a counter.
///
/// A Boost that reached nobody reports zeroes. That is a truthful result, not
/// a missing one — it must never be dressed up as success.
class BoostResults {
  const BoostResults({
    this.totalImpressions = 0,
    this.uniqueUsersReached = 0,
    this.likesReceived = 0,
    this.matchesCreated = 0,
    this.updatedAt,
  });

  static const BoostResults empty = BoostResults();

  /// Every time the profile appeared in someone's Discover page.
  final int totalImpressions;

  /// Distinct people reached during this Boost period.
  final int uniqueUsersReached;

  /// Likes from people who were actually shown the profile while boosted.
  final int likesReceived;

  /// Matches formed with people who were shown the profile while boosted.
  final int matchesCreated;

  final DateTime? updatedAt;

  /// True when the backend has not counted anything yet. Distinct from a
  /// finished Boost that genuinely reached nobody.
  bool get isEmpty =>
      totalImpressions == 0 &&
      uniqueUsersReached == 0 &&
      likesReceived == 0 &&
      matchesCreated == 0;

  /// Whether there is anything worth showing the user as a result.
  bool get hasAnyOutcome => likesReceived > 0 || matchesCreated > 0;
}
