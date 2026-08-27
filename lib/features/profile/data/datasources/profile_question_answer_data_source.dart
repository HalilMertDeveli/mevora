import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';

abstract class ProfileQuestionAnswerDataSource {
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  });

  Future<PartnerQuestionAnswersSnapshot> fetchPartnerAnswers(String partnerUid);

  Future<void> syncFromMatching();

  Future<void> setVisibility({
    required String questionId,
    required bool isVisible,
  });
}
