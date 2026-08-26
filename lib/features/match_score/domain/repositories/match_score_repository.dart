import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/match_score/domain/entities/match_score.dart';

abstract class MatchScoreRepository {
  Stream<MatchScoreSnapshot> watchScore(String uid);

  Future<Result<MatchScoreSnapshot>> getScore(String uid);

  Stream<List<MatchScoreHistoryEntry>> watchHistory(String uid);

  Stream<List<PendingMatchFeedback>> watchPendingFeedback(String uid);

  Future<Result<void>> submitFeedback({
    required String matchId,
    required String text,
  });

  Future<Result<void>> dismissFeedback({required String matchId});
}
