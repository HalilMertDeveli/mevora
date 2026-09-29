import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/data/datasources/relationship_data_source.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

/// In-memory relationship answers for mock builds and tests.
class MockRelationshipDataSource implements RelationshipDataSource {
  MockRelationshipDataSource({
    this.selfUid = 'self',
    Map<String, String>? answers,
  }) : _answers = Map<String, String>.from(answers ?? const {});

  final String selfUid;
  final Map<String, String> _answers;

  @override
  Future<RelationshipAnswerSnapshot> getAnswered() async {
    return _snapshot();
  }

  @override
  Future<RelationshipAnswerSnapshot> saveAnswer({
    required String questionId,
    required String answerId,
  }) async {
    if (!RelationshipQuestionCatalog.isValidAnswer(
      questionId: questionId,
      answerId: answerId,
    )) {
      throw StateError('invalid-relationship-answer');
    }
    _answers[questionId] = answerId;
    return _snapshot();
  }

  @override
  Future<Map<String, String>> getSavedAnswers(String uid) async {
    if (uid != selfUid) {
      return const {};
    }
    return Map<String, String>.from(_answers);
  }

  RelationshipAnswerSnapshot _snapshot() {
    return RelationshipAnswerSnapshot(
      answeredIds: _answers.keys.toSet(),
      answerCount: _answers.length,
    );
  }
}
