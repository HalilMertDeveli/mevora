import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';

class RelationshipAnswerSnapshot {
  const RelationshipAnswerSnapshot({
    this.answeredIds = const {},
    this.answerCount = 0,
    this.offerCooldownUntil,
  });

  final Set<String> answeredIds;
  final int answerCount;
  final DateTime? offerCooldownUntil;
}

abstract class RelationshipRepository {
  Future<Result<RelationshipAnswerSnapshot>> getAnswered();

  Future<Result<RelationshipAnswerSnapshot>> saveAnswer({
    required String questionId,
    required String answerId,
  });

  /// Persists offer cooldown. [matchTaken] true → 30 min break; false → 3 min.
  Future<Result<RelationshipAnswerSnapshot>> dismissOffer({
    bool matchTaken = false,
  });

  Future<Result<List<RelationshipMatchSuggestion>>> completeTest({
    required List<String> questionIds,
  });

  Future<Result<List<RelationshipMatchSuggestion>>> getSuggestions();

  /// Owner-only saved answers (questionId → answerId).
  Future<Result<Map<String, String>>> getSavedAnswers(String uid);
}
