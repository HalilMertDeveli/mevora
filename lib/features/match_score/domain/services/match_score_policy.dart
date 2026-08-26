/// Match points: 50 at signup, +1 unique match, +1 two-way chat in 3 days.
/// Only Cloud Functions increment scores. Feedback never changes them.
abstract final class MatchScorePolicy {
  static const int initialScore = 50;
  static const int matchBonus = 1;
  static const int interactionBonus = 1;
  static const Duration interactionWindow = Duration(days: 3);
  static const int feedbackMaxChars = 200;

  static int seed(int? current) {
    if (current == null) {
      return initialScore;
    }
    return current;
  }

  static bool shouldAwardMatchBonus({required bool alreadyAwarded}) {
    return !alreadyAwarded;
  }

  static bool isWithinInteractionWindow({
    required DateTime matchedAt,
    required DateTime now,
  }) {
    return !now.isAfter(matchedAt.add(interactionWindow));
  }

  static bool shouldAwardInteractionBonus({
    required bool alreadyAwarded,
    required DateTime matchedAt,
    required DateTime now,
    required Set<String> messagedUserIds,
    required List<String> userIds,
  }) {
    if (alreadyAwarded) {
      return false;
    }
    if (!isWithinInteractionWindow(matchedAt: matchedAt, now: now)) {
      return false;
    }
    if (userIds.length != 2) {
      return false;
    }
    return userIds.every(messagedUserIds.contains);
  }

  static bool canSubmitFeedback({
    required String uid,
    required bool isActive,
    required String? unmatchedBy,
    required bool alreadySubmitted,
  }) {
    if (alreadySubmitted || isActive) {
      return false;
    }
    final endedBy = unmatchedBy ?? '';
    if (endedBy.isEmpty || endedBy == uid) {
      return false;
    }
    return true;
  }
}
