import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';

class RelationshipAnswerSnapshot {
  const RelationshipAnswerSnapshot({
    this.answeredIds = const {},
    this.answerCount = 0,
    this.offerCooldownUntil,
    this.matchingEventCount = 0,
    this.matchingPaused = false,
  });

  final Set<String> answeredIds;
  final int answerCount;
  final DateTime? offerCooldownUntil;
  final int matchingEventCount;
  final bool matchingPaused;
}

abstract class RelationshipRepository {
  Future<Result<RelationshipAnswerSnapshot>> getAnswered();

  Future<Result<RelationshipAnswerSnapshot>> saveAnswer({
    required String questionId,
    required String answerId,
  });

  /// Persists offer cooldown / matching pause.
  ///
  /// [matchTaken] true → 30 min break; false → 3 min.
  /// Use [pauseMatching] / [continueMatching] for the continue prompt.
  Future<Result<RelationshipAnswerSnapshot>> dismissOffer({
    bool matchTaken = false,
    bool pauseMatching = false,
    bool continueMatching = false,
  });

  Future<Result<List<RelationshipMatchSuggestion>>> completeTest({
    required List<String> questionIds,
  });

  Future<Result<List<RelationshipMatchSuggestion>>> getSuggestions();

  /// Owner-only saved answers (questionId → answerId).
  Future<Result<Map<String, String>>> getSavedAnswers(String uid);
}
