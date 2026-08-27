import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';

abstract class ProfileQuestionAnswerRepository {
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  });

  /// Peer answers via Cloud Function — never reads peer Firestore docs.
  Future<Result<PartnerQuestionAnswersSnapshot>> fetchPartnerAnswers(
    String partnerUid,
  );

  Future<Result<void>> syncFromMatching();

  Future<Result<void>> setVisibility({
    required String questionId,
    required bool isVisible,
  });
}
