import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

class RelationshipCompatibility {
  const RelationshipCompatibility({
    required this.score,
    required this.sharedQuestionCount,
    required this.alignedCount,
    this.topTopics = const [],
  });

  /// alignedCount / sharedQuestionCount × 100, rounded. 0 if none shared.
  final int score;
  final int sharedQuestionCount;
  final int alignedCount;
  final List<RelationshipTopic> topTopics;

  bool get hasSignal => alignedCount > 0;
}

/// Same answers / questions both people answered × 100.
abstract final class RelationshipCompatibilityCalculator {
  static RelationshipCompatibility score({
    required Map<String, String> viewerAnswers,
    required Map<String, String> candidateAnswers,
  }) {
    if (viewerAnswers.isEmpty || candidateAnswers.isEmpty) {
      return const RelationshipCompatibility(
        score: 0,
        sharedQuestionCount: 0,
        alignedCount: 0,
      );
    }
    var shared = 0;
    var aligned = 0;
    final topicHits = <RelationshipTopic, int>{};
    for (final entry in viewerAnswers.entries) {
      final other = candidateAnswers[entry.key];
      if (other == null) {
        continue;
      }
      shared++;
      if (other == entry.value) {
        aligned++;
        final question = RelationshipQuestionCatalog.byId(entry.key);
        if (question != null) {
          topicHits[question.topic] = (topicHits[question.topic] ?? 0) + 1;
        }
      }
    }
    if (shared == 0) {
      return const RelationshipCompatibility(
        score: 0,
        sharedQuestionCount: 0,
        alignedCount: 0,
      );
    }
    final topics = topicHits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return RelationshipCompatibility(
      score: ((aligned / shared) * 100).round().clamp(0, 100),
      sharedQuestionCount: shared,
      alignedCount: aligned,
      topTopics: topics.take(3).map((item) => item.key).toList(),
    );
  }
}
