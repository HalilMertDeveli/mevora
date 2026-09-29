import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';

/// Relationship Learning and the member's control over what Mevora learns.
///
/// Every write goes through the server: answers are validated against the
/// server catalog, and learned preferences can only be reset, never written.
abstract interface class RelationshipLearningRepository {
  Future<Result<RelationshipLearningState>> loadState();

  /// Saves one answer. Idempotent on the server: re-sending the same answer
  /// changes nothing.
  Future<Result<LearningAnswerResult>> saveAnswer({
    required String questionId,
    required String answerId,
  });

  /// "Not now" for the follow-up round.
  Future<Result<void>> snoozeFollowUp();

  /// "Skip for now" on the onboarding Humor Lab step. Recorded server-side
  /// so the first-run journey moves on and never loops back.
  Future<Result<void>> skipOnboardingHumor();

  /// Clears what Mevora learned from interactions. Declared answers stay.
  Future<Result<void>> resetLearnedPreferences();
}
