import 'package:mevora/features/match_score/domain/entities/match_score.dart';

abstract class MatchScoreDataSource {
  Stream<MatchScoreSnapshot> watchScore(String uid);

  Future<MatchScoreSnapshot> getScore(String uid);

  Stream<List<MatchScoreHistoryEntry>> watchHistory(String uid);

  Stream<List<PendingMatchFeedback>> watchPendingFeedback(String uid);

  Future<void> submitFeedback({
    required String uid,
    required String matchId,
    required String text,
  });

  Future<void> dismissFeedback({
    required String uid,
    required String matchId,
  });
}
