import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_answer_comparison.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

/// Pure humor Q&A comparison for Why You Matched.
///
/// Uses relationship catalog metadata (read-only) to identify humor-tagged
/// questions: [RelationshipContentCategory.fun] or topics
/// [RelationshipTopic.flirting] / [RelationshipTopic.socialLife].
///
/// Does not modify the catalog. Does not invent answers.
abstract final class HumorAnswerComparator {
  /// Minimum questions both must have answered to emit any humor reason.
  static const minComparable = 2;

  /// Minimum matching answers for a reason.
  static const minMatching = 1;

  /// Minimum similarity score (0–100) for a reason.
  static const minScore = 60;

  /// Strong reasons require higher score and sample size.
  static const strongMinScore = 75;
  static const strongMinComparable = 3;

  static bool isHumorQuestion(RelationshipQuestion question) {
    if (question.category == RelationshipContentCategory.fun) {
      return true;
    }
    return question.topic == RelationshipTopic.flirting ||
        question.topic == RelationshipTopic.socialLife;
  }

  /// Deduplicates by questionId (last answer wins) and drops blanks.
  static Map<String, String> normalizeAnswers(
    Iterable<HumorQuestionAnswer> answers,
  ) {
    final out = <String, String>{};
    for (final item in answers) {
      final q = item.questionId.trim();
      final a = item.answerId.trim();
      if (q.isEmpty || a.isEmpty) {
        continue;
      }
      out[q] = a;
    }
    return out;
  }

  static HumorAnswerComparison compare({
    required Map<String, String> viewerAnswers,
    required Map<String, String> candidateAnswers,
  }) {
    if (viewerAnswers.isEmpty || candidateAnswers.isEmpty) {
      return HumorAnswerComparison.empty;
    }

    var comparable = 0;
    var matching = 0;
    final matchedIds = <String>[];

    for (final entry in viewerAnswers.entries) {
      final questionId = entry.key;
      final candidateAnswer = candidateAnswers[questionId];
      if (candidateAnswer == null) {
        continue;
      }

      final question = RelationshipQuestionCatalog.byId(questionId);
      if (question == null || !isHumorQuestion(question)) {
        continue;
      }

      // Invalid answer ids are still "comparable" only if both sides answered
      // the same catalog question with non-empty ids (already normalized).
      comparable++;
      if (entry.value == candidateAnswer) {
        matching++;
        matchedIds.add(questionId);
      }
    }

    if (comparable == 0) {
      return HumorAnswerComparison.empty;
    }

    final similarity = matching / comparable;
    final score = (similarity * 100).round().clamp(0, 100);

    return HumorAnswerComparison(
      comparableAnswers: comparable,
      matchingAnswers: matching,
      similarity: similarity,
      score: score,
      matchedQuestionIds: List.unmodifiable(matchedIds),
    );
  }

  /// Whether this comparison may produce a user-facing reason.
  static bool meetsReasonThreshold(HumorAnswerComparison comparison) {
    if (comparison.comparableAnswers < minComparable) {
      return false;
    }
    if (comparison.matchingAnswers < minMatching) {
      return false;
    }
    return comparison.score >= minScore;
  }

  /// Strong reason gate — insufficient sample stays moderate even if score high.
  static bool isStrong(HumorAnswerComparison comparison) {
    return meetsReasonThreshold(comparison) &&
        comparison.score >= strongMinScore &&
        comparison.comparableAnswers >= strongMinComparable;
  }

  /// Confidence from sample size and alignment (0.35–1.0 when valid).
  static double confidence(HumorAnswerComparison comparison) {
    if (comparison.comparableAnswers <= 0) {
      return 0;
    }
    final coverage =
        (comparison.comparableAnswers / 5).clamp(0.0, 1.0);
    final alignment = comparison.similarity;
    return (0.5 * coverage + 0.5 * alignment).clamp(0.35, 1.0);
  }
}
