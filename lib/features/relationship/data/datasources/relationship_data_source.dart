import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

abstract class RelationshipDataSource {
  Future<RelationshipAnswerSnapshot> getAnswered();

  Future<RelationshipAnswerSnapshot> saveAnswer({
    required String questionId,
    required String answerId,
  });

  /// Owner-only saved answers map (questionId → answerId).
  Future<Map<String, String>> getSavedAnswers(String uid);
}
