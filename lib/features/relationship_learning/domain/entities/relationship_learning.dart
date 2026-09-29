/// Relationship Learning — the questions Mevora asks so it can choose better
/// people. The server owns the catalog; the client renders what it receives
/// and never ships its own question copy.
library;

enum LearningQuestionKind {
  /// How much one compatibility dimension matters to the member.
  importance,

  /// How the member tends to do something; compared between two people.
  stance;

  static LearningQuestionKind parse(Object? raw) =>
      raw == 'importance' ? importance : stance;
}

class LearningOption {
  const LearningOption({
    required this.id,
    required this.labelTr,
    required this.labelEn,
  });

  final String id;
  final String labelTr;
  final String labelEn;

  String labelFor(String languageCode) =>
      languageCode == 'tr' ? labelTr : labelEn;
}

class LearningQuestion {
  const LearningQuestion({
    required this.id,
    required this.version,
    required this.kind,
    required this.dimension,
    required this.promptTr,
    required this.promptEn,
    required this.options,
    this.answerId,
  });

  final String id;
  final int version;
  final LearningQuestionKind kind;

  /// The compatibility dimension this question informs (relationship,
  /// values, lifestyle, interests, music, humor).
  final String dimension;
  final String promptTr;
  final String promptEn;
  final List<LearningOption> options;

  /// The member's saved answer, if any.
  final String? answerId;

  bool get isAnswered => answerId != null;

  String promptFor(String languageCode) =>
      languageCode == 'tr' ? promptTr : promptEn;

  LearningQuestion withAnswer(String? answer) => LearningQuestion(
    id: id,
    version: version,
    kind: kind,
    dimension: dimension,
    promptTr: promptTr,
    promptEn: promptEn,
    options: options,
    answerId: answer,
  );
}

/// The compact progress block the server attaches to Picks and answers.
class LearningSummary {
  const LearningSummary({
    this.required = false,
    this.initialTotal = 15,
    this.initialAnswered = 0,
    this.initialCompleted = false,
    this.blocksPicks = false,
    this.progressiveDue = false,
    this.followUpSize = 3,
  });

  /// Nothing known yet: never blocks, never prompts.
  static const LearningSummary unknown = LearningSummary(
    initialCompleted: true,
  );

  /// A member who joined after Relationship Learning shipped.
  final bool required;
  final int initialTotal;
  final int initialAnswered;
  final bool initialCompleted;

  /// Today's Picks wait until the initial questions are done.
  final bool blocksPicks;

  /// A follow-up round is ready and it has been long enough to invite them.
  final bool progressiveDue;

  /// Questions in one follow-up round.
  final int followUpSize;

  /// An existing member who has not (fully) answered yet: invite, never block.
  bool get invitesInitial => !initialCompleted && !blocksPicks;
}

class RelationshipLearningState {
  const RelationshipLearningState({
    required this.summary,
    required this.initialQuestions,
    required this.followUpQuestions,
  });

  final LearningSummary summary;

  /// The initial set, in order, each with the member's saved answer.
  final List<LearningQuestion> initialQuestions;

  /// The current follow-up round (empty until the initial set is done).
  final List<LearningQuestion> followUpQuestions;
}

class LearningAnswerResult {
  const LearningAnswerResult({
    required this.summary,
    this.completedInitialNow = false,
    this.completedRoundNow = false,
  });

  final LearningSummary summary;
  final bool completedInitialNow;
  final bool completedRoundNow;
}
