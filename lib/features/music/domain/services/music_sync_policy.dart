/// Prevents hammering the Spotify Web API. Enforced on client and Functions.
abstract final class MusicSyncPolicy {
  static const Duration minInterval = Duration(hours: 6);

  static bool canSync({
    required DateTime now,
    DateTime? lastSyncedAt,
  }) {
    if (lastSyncedAt == null) {
      return true;
    }
    return now.difference(lastSyncedAt) >= minInterval;
  }

  static Duration? cooldownRemaining({
    required DateTime now,
    DateTime? lastSyncedAt,
  }) {
    if (lastSyncedAt == null) {
      return null;
    }
    final elapsed = now.difference(lastSyncedAt);
    if (elapsed >= minInterval) {
      return null;
    }
    return minInterval - elapsed;
  }
}
