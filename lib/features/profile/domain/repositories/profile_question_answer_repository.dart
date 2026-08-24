import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';

abstract class ProfileQuestionAnswerRepository {
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  });

  Future<Result<void>> syncFromMatching();

  Future<Result<void>> setVisibility({
    required String questionId,
    required bool isVisible,
  });
}
