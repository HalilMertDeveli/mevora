import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

class ProfileQuestionAnswerDisplay {
  const ProfileQuestionAnswerDisplay({
    required this.answer,
    required this.questionText,
    required this.answerText,
  });

  final ProfileQuestionAnswer answer;
  final String questionText;
  final String answerText;

  static ProfileQuestionAnswerDisplay? resolve(
    ProfileQuestionAnswer answer,
    String locale,
  ) {
    final question = RelationshipQuestionCatalog.byId(answer.questionId);
    if (question == null || answer.answerId.isEmpty) {
      return null;
    }
    final option = question.answers
        .where((item) => item.id == answer.answerId)
        .firstOrNull;
    if (option == null) {
      return null;
    }
    return ProfileQuestionAnswerDisplay(
      answer: answer,
      questionText: question.promptFor(locale),
      answerText: option.labelFor(locale),
    );
  }
}
