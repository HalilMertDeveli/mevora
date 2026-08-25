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
}
