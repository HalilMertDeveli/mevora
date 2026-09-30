import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';

/// Daily relationship questions and the member's control over what Mevora
/// learns.
///
/// Every write goes through the server: answers are validated against the
/// server's set for the server's day, and learned preferences can only be
/// reset, never written.
abstract interface class RelationshipLearningRepository {
  Future<Result<RelationshipLearningState>> loadState();

  /// Saves one answer to today's set. Idempotent on the server: re-sending
  /// the same answer changes nothing.
  Future<Result<DailyAnswerResult>> saveDailyAnswer({
    required String questionSetId,
    required String questionId,
    required int questionVersion,
    required String answerId,
  });

  /// Changes an answer given earlier (the dashboard). Never answers a new
  /// question.
  Future<Result<void>> updateAnswer({
    required String questionId,
    required int questionVersion,
    required String answerId,
  });

  /// "Bugünlük geç": puts today's set away until the next day.
  Future<Result<LearningSummary>> skipToday();

  /// "Skip for now" on the onboarding Humor Lab step. Recorded server-side
  /// so the first-run journey moves on and never loops back.
  Future<Result<void>> skipOnboardingHumor();

  /// Clears what Mevora learned from interactions. Declared answers stay.
  Future<Result<void>> resetLearnedPreferences();
}

/// The failure message for an answer sent to a set whose day has passed:
/// the flow reloads today's set instead of reporting an error.
const String learningStaleSetReason = 'stale-set';
