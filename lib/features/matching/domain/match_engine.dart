import 'package:mevora/features/matching/domain/models/like_record.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';

/// Canonical matching rules. Cloud Functions are the only writer of
/// `matches/{id}`; this engine is the shared validation oracle.
abstract final class MatchEngine {
  static String likeId({required String fromUserId, required String toUserId}) {
    return '${fromUserId}_$toUserId';
  }

  /// Deterministic match id from two Firebase UIDs. Prevents duplicate pairs.
  static String matchId(String uidA, String uidB) {
    final parts = [uidA, uidB]..sort();
    return '${parts[0]}_${parts[1]}';
  }

  static bool isValidPair(String uidA, String uidB) {
    return uidA.isNotEmpty && uidB.isNotEmpty && uidA != uidB;
  }

  static bool canRecordSwipe({
    required String actorUid,
    required String targetUid,
    required bool alreadySwiped,
    required bool blocked,
  }) {
    return isValidPair(actorUid, targetUid) && !alreadySwiped && !blocked;
  }

  static bool shouldCreateMatch({
    required LikeRecord? forward,
    required LikeRecord? reverse,
    required bool blocked,
    required bool existingActiveMatch,
  }) {
    if (blocked || existingActiveMatch) {
      return false;
    }
    if (forward == null || reverse == null) {
      return false;
    }
    if (forward.fromUserId == forward.toUserId) {
      return false;
    }
    return forward.isPositive && reverse.isPositive;
  }

  static Match buildMatch({
    required String uidA,
    required String uidB,
    required DateTime createdAt,
    Map<String, String> names = const {},
    Map<String, String> photos = const {},
  }) {
    final ids = [uidA, uidB]..sort();
    return Match(
      id: matchId(uidA, uidB),
      userIds: ids,
      createdAt: createdAt,
      isActive: true,
      unreadCounts: {uidA: 0, uidB: 0},
      isNewFor: {uidA: true, uidB: true},
      participantNames: names,
      participantPhotos: photos,
    );
  }

  static LikeRecord buildLike({
    required String fromUserId,
    required String toUserId,
    required SwipeAction action,
    required DateTime createdAt,
  }) {
    return LikeRecord(
      id: likeId(fromUserId: fromUserId, toUserId: toUserId),
      fromUserId: fromUserId,
      toUserId: toUserId,
      action: action,
      createdAt: createdAt,
    );
  }
}
