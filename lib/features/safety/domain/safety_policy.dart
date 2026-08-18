abstract final class SafetyPolicy {
  static String blockId({required String blockerId, required String blockedUserId}) {
    return '${blockerId}_$blockedUserId';
  }

  static bool isBlocked({
    required Set<String> blockIds,
    required String uidA,
    required String uidB,
  }) {
    return blockIds.contains(blockId(blockerId: uidA, blockedUserId: uidB)) ||
        blockIds.contains(blockId(blockerId: uidB, blockedUserId: uidA));
  }

  static bool canInteract({
    required bool matchActive,
    required bool blocked,
  }) {
    return matchActive && !blocked;
  }

  static bool canCreateMatch({required bool blocked}) => !blocked;
}

/// Retention is a backend concern. UI must never mass-delete messages.
abstract class ChatRetentionPolicy {
  Future<void> scheduleAfterUnmatch({required String matchId});
}

class NoOpChatRetentionPolicy implements ChatRetentionPolicy {
  const NoOpChatRetentionPolicy();

  @override
  Future<void> scheduleAfterUnmatch({required String matchId}) async {}
}

abstract class SafetyRepository {
  Future<void> unmatch({required String matchId});

  Future<void> blockUser({
    required String userId,
    String? matchId,
  });

  Future<void> reportUser({
    required String userId,
    required String reason,
    String? matchId,
    String? messageId,
    String? description,
  });

  Future<bool> isBlockedPair(String uidA, String uidB);

  Stream<Set<String>> watchBlockedUserIds(String uid);
}
