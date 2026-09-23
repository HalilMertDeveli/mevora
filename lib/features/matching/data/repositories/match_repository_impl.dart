import 'package:mevora/features/matching/data/datasources/firebase_match_data_source.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

class MatchRepositoryImpl implements MatchRepository, LikeRepository {
  MatchRepositoryImpl({required FirebaseMatchDataSource dataSource})
    : _dataSource = dataSource;

  final FirebaseMatchDataSource _dataSource;

  @override
/// Deletion history is a Firestore-backed concept; nothing to surface here.
  @override
  Stream<List<MatchListItem>> watchArchivedMatches(String uid) =>
      const Stream<List<MatchListItem>>.empty();

  @override
  Stream<List<MatchListItem>> watchMatches(String uid) {
    return _dataSource.watchMatches(uid);
  }

  @override
  Future<Match?> getMatch(String matchId) => _dataSource.getMatch(matchId);

  @override
  Stream<Match?> watchMatch(String matchId) => _dataSource.watchMatch(matchId);

  @override
  Future<void> markOpened(String matchId, String uid) {
    return _dataSource.markOpened(matchId, uid);
  }

  @override
  Future<SwipeResultWrapper> recordSwipe({
    required String targetUserId,
    required String action,
  }) {
    return _dataSource.recordSwipe(
      targetUserId: targetUserId,
      action: action,
    );
  }
}
