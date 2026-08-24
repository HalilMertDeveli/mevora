class ProfileQuestionAnswer {
  const ProfileQuestionAnswer({
    required this.questionId,
    required this.answerId,
    required this.isVisible,
    this.createdAt,
    this.updatedAt,
  });

  final String questionId;
  final String answerId;
  final bool isVisible;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
