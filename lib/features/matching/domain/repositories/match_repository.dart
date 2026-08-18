import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';

class SwipeResultWrapper {
  const SwipeResultWrapper({
    required this.matched,
    this.match,
  });

  final bool matched;
  final Match? match;
}

class PresenceWatch {
  const PresenceWatch({
    required this.updatedAt,
    this.hideOnlineStatus = false,
  });

  final DateTime? updatedAt;
  final bool hideOnlineStatus;
}

abstract class MatchRepository {
  Stream<List<MatchListItem>> watchMatches(String uid);

  Future<Match?> getMatch(String matchId);

  Stream<Match?> watchMatch(String matchId);

  Future<void> markOpened(String matchId, String uid);
}

abstract class LikeRepository {
  Future<SwipeResultWrapper> recordSwipe({
    required String targetUserId,
    required String action,
  });
}

abstract class DiscoveryExclusionSource {
  Stream<Set<String>> watchHiddenUserIds(String uid);
}

abstract class PresenceRepository {
  Stream<PresenceWatch> watch(String uid);

  Future<void> heartbeat(String uid, {required bool hideOnlineStatus});
}
