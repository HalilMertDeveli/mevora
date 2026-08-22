import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/match_score/data/datasources/match_score_data_source.dart';
import 'package:mevora/features/match_score/domain/entities/match_score.dart';
import 'package:mevora/features/match_score/domain/repositories/match_score_repository.dart';

class MatchScoreRepositoryImpl implements MatchScoreRepository {
  MatchScoreRepositoryImpl({
    required MatchScoreDataSource dataSource,
    required AuthUidSource uidSource,
  }) : _dataSource = dataSource,
       _uidSource = uidSource;

  final MatchScoreDataSource _dataSource;
  final AuthUidSource _uidSource;

  @override
  Stream<MatchScoreSnapshot> watchScore(String uid) {
    return _dataSource.watchScore(uid);
  }

  @override
  Future<Result<MatchScoreSnapshot>> getScore(String uid) async {
    try {
      return Success(await _dataSource.getScore(uid));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Stream<List<MatchScoreHistoryEntry>> watchHistory(String uid) {
    return _dataSource.watchHistory(uid);
  }

  @override
  Stream<List<PendingMatchFeedback>> watchPendingFeedback(String uid) {
    return _dataSource.watchPendingFeedback(uid);
  }

  @override
  Future<Result<void>> submitFeedback({
    required String matchId,
    required String text,
  }) async {
    final uid = _uidSource.currentUid;
    if (uid == null || uid.isEmpty) {
      return const Err(AuthzFailure('unauthenticated'));
    }
    try {
      await _dataSource.submitFeedback(uid: uid, matchId: matchId, text: text);
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<void>> dismissFeedback({required String matchId}) async {
    final uid = _uidSource.currentUid;
    if (uid == null || uid.isEmpty) {
      return const Err(AuthzFailure('unauthenticated'));
    }
    try {
      await _dataSource.dismissFeedback(uid: uid, matchId: matchId);
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}
