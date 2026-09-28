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
    this.isOnline = false,
    required this.updatedAt,
    this.lastSeenAt,
  });

  final bool isOnline;
  final DateTime? updatedAt;
  final DateTime? lastSeenAt;
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

  Future<void> setOnline(String uid);

  Future<void> setOffline(String uid);

  Future<void> heartbeat(String uid);
}
