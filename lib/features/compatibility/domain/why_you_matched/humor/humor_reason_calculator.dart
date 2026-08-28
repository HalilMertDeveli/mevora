import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_category.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_evidence.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_answer_comparator.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_answer_comparison.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';

/// Builds a single humor [WhyYouMatchedReason] from real comparison data.
///
/// Priority:
/// 1. Humor-tagged relationship Q&A answers (measurable N-of-M evidence)
/// 2. Humor Lab vector compatibility (Phase 2 matrix primary signal)
///
/// Returns null when data is missing or below thresholds — never invents.
abstract final class HumorReasonCalculator {
  static const labMinScore = 60;
  static const labMinConfidence = 0.15;

  static WhyYouMatchedReason? fromAnswers({
    required String candidateUid,
    required HumorAnswerComparison comparison,
  }) {
    if (!HumorAnswerComparator.meetsReasonThreshold(comparison)) {
      return null;
    }

    final score = comparison.score;
    final WhyYouMatchedStrength strength;
    if (HumorAnswerComparator.isStrong(comparison)) {
      strength = WhyYouMatchedStrength.strong;
    } else if (comparison.comparableAnswers <
        HumorAnswerComparator.strongMinComparable) {
      // Insufficient sample — never emit strong even if score is high.
      strength = score >= 50
          ? WhyYouMatchedStrength.moderate
          : WhyYouMatchedStrength.weak;
    } else {
      strength = WhyYouMatchedStrengthX.fromScore(score);
    }
    final confidence = HumorAnswerComparator.confidence(comparison);

    // Score ↔ text consistency: description always uses matching/comparable.
    final created = WhyYouMatchedReason.create(
      id: 'humor_answers_$candidateUid',
      category: WhyYouMatchedCategory.humor,
      score: score,
      strength: strength,
      title: 'wymHumorTitle',
      description: 'wymHumorEvidence',
      descriptionArgs: [
        '${comparison.matchingAnswers}',
        '${comparison.comparableAnswers}',
      ],
      evidence: WhyYouMatchedEvidence(
        type: 'sharedHumorAnswers',
        values: {
          'comparable': comparison.comparableAnswers,
          'matching': comparison.matchingAnswers,
          'similarity': comparison.similarity,
          'score': score,
          'matchedQuestionIds': comparison.matchedQuestionIds,
        },
      ),
      confidence: confidence,
      priority: (score * confidence).round(),
    );
    return created.reason;
  }

  static WhyYouMatchedReason? fromHumorLab({
    required String candidateUid,
    required HumorCompatibility humor,
  }) {
    if (!humor.available || humor.score == null) {
      return null;
    }
    final score = humor.score!.clamp(0, 100);
    if (score < labMinScore || humor.confidence < labMinConfidence) {
      return null;
    }

    final shared = humor.strongestShared.map((e) => e.name).toList();
    // Measurable dimension evidence when shared dims exist.
    final comparable = shared.isNotEmpty ? 11 : 0;
    final matching = shared.length;

    final descriptionKey = shared.isNotEmpty
        ? 'wymHumorDimsEvidence'
        : 'wymHumorScoreEvidence';
    final descriptionArgs = shared.isNotEmpty
        ? ['$matching', '$comparable']
        : ['$score'];

    final created = WhyYouMatchedReason.create(
      id: 'humor_lab_$candidateUid',
      category: WhyYouMatchedCategory.humor,
      score: score,
      title: 'wymHumorTitle',
      description: descriptionKey,
      descriptionArgs: descriptionArgs,
      evidence: WhyYouMatchedEvidence(
        type: 'humorVectorSimilarity',
        values: {
          'score': score,
          'confidence': humor.confidence,
          'sharedDims': shared,
          if (shared.isNotEmpty) ...{
            'comparable': comparable,
            'matching': matching,
          },
        },
      ),
      confidence: humor.confidence.clamp(0.0, 1.0),
      priority: (score * humor.confidence).round(),
    );
    return created.reason;
  }
}
