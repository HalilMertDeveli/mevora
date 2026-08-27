import 'package:mevora/features/relationship/domain/entities/matching_game_round.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

abstract class RelationshipDataSource {
  Future<RelationshipAnswerSnapshot> getAnswered();

  Future<RelationshipAnswerSnapshot> saveAnswer({
    required String questionId,
    required String answerId,
  });

  Future<RelationshipAnswerSnapshot> dismissOffer({
    bool matchTaken = false,
    bool pauseMatching = false,
    bool continueMatching = false,
  });

  Future<List<RelationshipMatchSuggestion>> completeTest({
    required List<String> questionIds,
  });

  Future<List<RelationshipMatchSuggestion>> getSuggestions();

  /// Owner-only saved answers map (questionId → answerId).
  Future<Map<String, String>> getSavedAnswers(String uid);

  Future<MatchingGameRoundInfo> getMatchingGameRound();

  Future<void> joinMatchingGameRound(String roundId);

  Future<MatchingGameResultInfo> submitMatchingGameAnswers({
    required String roundId,
    required List<String> questionIds,
    required Map<String, String> answers,
  });

  Future<MatchingGameResultInfo> getMatchingGameResult(String roundId);
}
