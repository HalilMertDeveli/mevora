import 'dart:async';

import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

class FakeMatchRepository
    implements MatchRepository, LikeRepository, PresenceRepository {
  FakeMatchRepository({this.uid = 'user-1'});

  final String uid;
  final Map<String, Match> matches = {};
  final _matchController = StreamController<List<MatchListItem>>.broadcast();
  final _presence = <String, PresenceWatch>{};

  void seed(Match match) {
    matches[match.id] = match;
    _matchController.add(_items);
  }

  List<MatchListItem> get _items {
    return [
      for (final match in matches.values)
        if (match.isParticipant(uid))
          MatchListItem(
            match: match,
            otherUserId: match.otherUserId(uid),
            name: match.otherName(uid),
            photoUrl: match.otherPhoto(uid),
          ),
    ];
  }

  @override
  Stream<List<MatchListItem>> watchMatches(String userId) => _matchController.stream;

  @override
  Future<Match?> getMatch(String matchId) async => matches[matchId];

  @override
  Stream<Match?> watchMatch(String matchId) async* {
    yield matches[matchId];
  }

  @override
  Future<void> markOpened(String matchId, String userId) async {
    final match = matches[matchId];
    if (match == null) {
      return;
    }
    matches[matchId] = match.copyWith(
      isNewFor: {...match.isNewFor, userId: false},
      unreadCounts: {...match.unreadCounts, userId: 0},
    );
    _matchController.add(_items);
  }

  @override
  Future<SwipeResultWrapper> recordSwipe({
    required String targetUserId,
    required String action,
  }) async {
    final swipe = SwipeActionX.fromWire(action);
    if (!swipe.canCreateMatch) {
      return const SwipeResultWrapper(matched: false);
    }
    final match = Match(
      id: 'match-$uid-$targetUserId',
      userIds: [uid, targetUserId],
      createdAt: DateTime.utc(2026, 8, 18),
      isActive: true,
      participantNames: {uid: 'Ada', targetUserId: 'Grace'},
    );
    matches[match.id] = match;
    _matchController.add(_items);
    return SwipeResultWrapper(matched: true, match: match);
  }

  @override
  Stream<PresenceWatch> watch(String userId) async* {
    yield _presence[userId] ?? const PresenceWatch(updatedAt: null);
  }

  @override
  Future<void> setOnline(String userId) async {
    _presence[userId] = PresenceWatch(
      isOnline: true,
      updatedAt: DateTime.utc(2026, 8, 18, 12),
    );
  }

  @override
  Future<void> setOffline(String userId) async {
    _presence[userId] = PresenceWatch(
      isOnline: false,
      updatedAt: DateTime.utc(2026, 8, 18, 12),
      lastSeenAt: DateTime.utc(2026, 8, 18, 12),
    );
  }

  @override
  Future<void> heartbeat(String userId) async {
    _presence[userId] = PresenceWatch(
      isOnline: true,
      updatedAt: DateTime.utc(2026, 8, 18, 12),
      lastSeenAt: _presence[userId]?.lastSeenAt,
    );
  }

  void dispose() {
    unawaited(_matchController.close());
  }
}
