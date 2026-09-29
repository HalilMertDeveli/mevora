import 'package:mevora/core/errors/result.dart';

class RelationshipAnswerSnapshot {
  const RelationshipAnswerSnapshot({
    this.answeredIds = const {},
    this.answerCount = 0,
  });

  final Set<String> answeredIds;
  final int answerCount;
}

/// The member's answers to the relationship question catalog (shown on
/// their profile and compared with other people's). The timed test offer
/// that used to live here was retired; Relationship Learning replaced it.
abstract class RelationshipRepository {
  Future<Result<RelationshipAnswerSnapshot>> getAnswered();

  Future<Result<RelationshipAnswerSnapshot>> saveAnswer({
    required String questionId,
    required String answerId,
  });

  /// Owner-only saved answers (questionId → answerId).
  Future<Result<Map<String, String>>> getSavedAnswers(String uid);
}
