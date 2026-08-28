/// One verified humor-related question answer for a user.
class HumorQuestionAnswer {
  const HumorQuestionAnswer({
    required this.questionId,
    required this.answerId,
  });

  final String questionId;
  final String answerId;
}

/// Result of comparing two users' humor-related answers.
///
/// All counts are derived from real answer maps — never invented.
class HumorAnswerComparison {
  const HumorAnswerComparison({
    required this.comparableAnswers,
    required this.matchingAnswers,
    required this.similarity,
    required this.score,
    required this.matchedQuestionIds,
  });

  /// Questions both users answered (humor-tagged only).
  final int comparableAnswers;

  /// Questions where both chose the same answerId.
  final int matchingAnswers;

  /// matching / comparable in \[0, 1\].
  final double similarity;

  /// Round(similarity × 100), clamped 0–100.
  final int score;

  final List<String> matchedQuestionIds;

  bool get hasComparableData => comparableAnswers > 0;

  static const empty = HumorAnswerComparison(
    comparableAnswers: 0,
    matchingAnswers: 0,
    similarity: 0,
    score: 0,
    matchedQuestionIds: [],
  );
}
