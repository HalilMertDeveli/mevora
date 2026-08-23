/// Real-data insight for the "Someone is thinking like you" discover card.
class HiddenCompatibilityInsight {
  const HiddenCompatibilityInsight({
    required this.candidateUid,
    required this.overallScore,
    required this.questionScore,
    required this.alignedCount,
    required this.sharedQuestionCount,
  });

  final String candidateUid;
  final int overallScore;
  final int questionScore;
  final int alignedCount;
  final int sharedQuestionCount;
}
