/// Relationship questions — the Core questions Mevora asks every member in
/// the same order (fifteen at onboarding, then five a day) so it can choose
/// better people. The server owns the bank, the order, the day and the set;
/// the client renders what it receives and never ships its own question copy.
library;

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
    required this.category,
    required this.dimension,
    required this.promptTr,
    required this.promptEn,
    required this.options,
    this.answerType = 'choice',
    this.answerId,
  });

  /// Stable versioned id, e.g. `relationship_daily_contact_v1`.
  final String id;

  /// The question version the member saw; sent back with the answer.
  final int version;

  /// Dashboard area (relationship, communication, lifestyle, values, humor,
  /// music, interests).
  final String category;

  /// The compatibility dimension this question informs.
  final String dimension;

  /// `choice` or `scale`; both render as a list of options.
  final String answerType;
  final String promptTr;
  final String promptEn;
  final List<LearningOption> options;

  /// The member's answer for today (daily set) or their saved answer
  /// (dashboard), if any.
  final String? answerId;

  bool get isAnswered => answerId != null;

  String promptFor(String languageCode) =>
      languageCode == 'tr' ? promptTr : promptEn;

  LearningQuestion withAnswer(String? answer) => LearningQuestion(
    id: id,
    version: version,
    category: category,
    dimension: dimension,
    answerType: answerType,
    promptTr: promptTr,
    promptEn: promptEn,
    options: options,
    answerId: answer,
  );
}

/// Today's progress, for the server's logical day.
class DailyProgress {
  const DailyProgress({
    this.dateKey = '',
    this.questionSetId,
    this.total = 0,
    this.answered = 0,
    this.completed = false,
    this.skipped = false,
    this.canSkip = true,
  });

  /// `YYYY-MM-DD` in Mevora's day (Europe/Istanbul), decided by the server.
  final String dateKey;

  /// The member's set for this day; null until known.
  final String? questionSetId;

  /// How many questions today's set holds: fifteen at onboarding, five a
  /// day after that, fewer when little is left. Always from the server.
  final int total;
  final int answered;
  final bool completed;

  /// "Bugünlük geç" was chosen for this day.
  final bool skipped;

  /// False only for a new member's onboarding questions.
  final bool canSkip;

  bool get started => answered > 0;
}

/// The compact progress block the server attaches to Picks and answers.
class LearningSummary {
  const LearningSummary({
    this.required = false,
    this.blocksPicks = false,
    this.firstSetCompleted = false,
    this.humorCalibrated = false,
    this.journeyStage = JourneyStage.done,
    this.today = const DailyProgress(),
    this.nextDayStartsAt,
  });

  /// Nothing known yet: never blocks, never prompts.
  static const LearningSummary unknown = LearningSummary(
    firstSetCompleted: true,
    today: DailyProgress(completed: true),
  );

  /// A member who joined after daily questions shipped.
  final bool required;

  /// A new member's Picks wait for the onboarding questions.
  final bool blocksPicks;
  final bool firstSetCompleted;

  /// Humor Lab calibration is complete (only on full learning state).
  final bool humorCalibrated;

  /// The journey step this member is on (only on full learning state).
  final JourneyStage journeyStage;
  final DailyProgress today;

  /// When the server's next logical day begins.
  final DateTime? nextDayStartsAt;

  /// Today's set is open and the member has not put it away for today.
  bool get invitesToday => !blocksPicks && !today.completed && !today.skipped;
}

/// The member's set for today, in the order every member meets it.
class DailyQuestionSet {
  const DailyQuestionSet({
    required this.dateKey,
    required this.questionSetId,
    required this.questions,
  });

  static const DailyQuestionSet empty = DailyQuestionSet(
    dateKey: '',
    questionSetId: '',
    questions: [],
  );

  final String dateKey;
  final String questionSetId;

  /// In order, each with the member's answer if they gave one.
  final List<LearningQuestion> questions;
}

class RelationshipLearningState {
  const RelationshipLearningState({
    required this.summary,
    required this.today,
    this.overview = LearningOverview.empty,
  });

  final LearningSummary summary;
  final DailyQuestionSet today;

  /// The learning dashboard: coverage, totals, read-backs and answers.
  final LearningOverview overview;
}

class DailyAnswerResult {
  const DailyAnswerResult({
    required this.summary,
    this.completedTodayNow = false,
    this.firstSetCompletedNow = false,
  });

  final LearningSummary summary;
  final bool completedTodayNow;
  final bool firstSetCompletedNow;
}

/// Where a member is in the first-run / daily journey (server-decided):
///
///   new member:  humor -> daily -> done
///   every day:   daily (until today's set is done or skipped) -> done
enum JourneyStage {
  humor,
  daily,
  done;

  static JourneyStage parse(Object? raw) => switch (raw) {
    'humor' => humor,
    'daily' => daily,
    _ => done,
  };
}

/// One compatibility category on the learning dashboard. Plain coverage:
/// answered questions plus existing profile signals, over what exists.
class LearningCategoryProgress {
  const LearningCategoryProgress({
    required this.key,
    required this.answered,
    required this.questions,
    required this.signals,
    required this.signalsPossible,
    required this.progress,
  });

  final String key;
  final int answered;
  final int questions;
  final int signals;
  final int signalsPossible;

  /// 0..1, computed by the server.
  final double progress;
}

/// A soft read-back of one of the member's own answers.
class LearningHighlight {
  const LearningHighlight({
    required this.questionId,
    required this.category,
    required this.textTr,
    required this.textEn,
  });

  final String questionId;
  final String category;
  final String textTr;
  final String textEn;

  String textFor(String languageCode) => languageCode == 'tr' ? textTr : textEn;
}

/// An answered question, for viewing and changing the answer.
class AnsweredLearningQuestion {
  const AnsweredLearningQuestion({required this.question, this.answeredAt});

  final LearningQuestion question;
  final DateTime? answeredAt;

  String get category => question.category;
}

/// Real counts, straight from the server.
class LearningTotals {
  const LearningTotals({
    this.thisMonth = 0,
    this.total = 0,
    this.completedDays = 0,
  });

  final int thisMonth;
  final int total;
  final int completedDays;
}

class LearningOverview {
  const LearningOverview({
    this.overallProgress = 0,
    this.categories = const [],
    this.totals = const LearningTotals(),
    this.highlights = const [],
    this.answered = const [],
  });

  static const LearningOverview empty = LearningOverview();

  final double overallProgress;
  final List<LearningCategoryProgress> categories;
  final LearningTotals totals;
  final List<LearningHighlight> highlights;
  final List<AnsweredLearningQuestion> answered;
}
