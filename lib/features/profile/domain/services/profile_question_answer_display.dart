import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

class ProfileQuestionAnswerDisplay {
  const ProfileQuestionAnswerDisplay({
    required this.answer,
    required this.questionText,
    required this.answerText,
    this.isLocked = false,
  });

  final ProfileQuestionAnswer answer;
  final String questionText;
  final String answerText;
  final bool isLocked;

  static ProfileQuestionAnswerDisplay? resolve(
    ProfileQuestionAnswer answer,
    String locale,
  ) {
    final question = RelationshipQuestionCatalog.byId(answer.questionId);
    if (question == null) {
      return null;
    }
    final questionText = question.promptFor(locale);
    if (answer.answerLocked || answer.answerId.isEmpty) {
      return ProfileQuestionAnswerDisplay(
        answer: answer,
        questionText: questionText,
        answerText: '',
        isLocked: true,
      );
    }
    final option = question.answers
        .where((item) => item.id == answer.answerId)
        .firstOrNull;
    if (option == null) {
      return null;
    }
    return ProfileQuestionAnswerDisplay(
      answer: answer,
      questionText: questionText,
      answerText: option.labelFor(locale),
    );
  }
}
