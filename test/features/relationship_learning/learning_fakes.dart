import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// A question as the server would send it.
LearningQuestion learningQuestion(
  int n, {
  String? answer,
  String category = 'values',
  int version = 1,
}) {
  return LearningQuestion(
    id: 'relationship_q${n}_v$version',
    version: version,
    category: category,
    dimension: category == 'communication' ? 'relationship' : category,
    promptTr: 'Soru $n?',
    promptEn: 'Question $n?',
    options: const [
      LearningOption(id: 'a', labelTr: 'Birinci', labelEn: 'First'),
      LearningOption(id: 'b', labelTr: 'İkinci', labelEn: 'Second'),
      LearningOption(id: 'c', labelTr: 'Üçüncü', labelEn: 'Third'),
    ],
    answerId: answer,
  );
}

/// Behaves like the server: one set per day, validates every answer
/// against it, stores, completes exactly once, and rejects yesterday's set.
class FakeRelationshipLearningRepository
    implements RelationshipLearningRepository {
  FakeRelationshipLearningRepository({
    int count = 10,
    int answered = 0,
    this.required = false,
    bool firstSetCompleted = false,
    this.dateKey = '2026-09-29',
    List<LearningQuestion>? earlier,
  }) : _firstSetCompleted = firstSetCompleted || !required,
       earlier = earlier ?? [] {
    _fill(count, answered, offset: 0);
    if (answered >= count) {
      _completed = true;
      _firstSetCompleted = true;
      completions = 1;
    }
    journeyStage = _completed ? JourneyStage.done : JourneyStage.daily;
  }

  final bool required;
  String dateKey;
  final List<LearningQuestion> today = [];

  /// Answers from earlier days (dashboard only).
  final List<LearningQuestion> earlier;
  final List<(String, String, int, String)> saves = [];
  final List<(String, String)> updates = [];
  int loads = 0;
  int skips = 0;
  int resets = 0;
  int humorSkips = 0;
  int completions = 0;
  late JourneyStage journeyStage;
  bool humorCalibrated = false;
  bool failSaves = false;
  bool failLoads = false;
  bool failReset = false;
  bool failSkip = false;
  bool _completed = false;
  bool _skipped = false;
  bool _firstSetCompleted;
  int thisMonth = 0;
  List<LearningCategoryProgress> categories = const [
    LearningCategoryProgress(
      key: 'relationship',
      answered: 2,
      questions: 12,
      signals: 1,
      signalsPossible: 1,
      progress: 0.23,
    ),
    LearningCategoryProgress(
      key: 'communication',
      answered: 1,
      questions: 8,
      signals: 0,
      signalsPossible: 0,
      progress: 0.13,
    ),
  ];
  List<LearningHighlight> highlights = const [
    LearningHighlight(
      questionId: 'relationship_q1_v1',
      category: 'relationship',
      textTr: 'Adım adım ilerlemeye daha yakınsın.',
      textEn: 'You lean towards taking things step by step.',
    ),
  ];

  String get questionSetId => 'daily-$dateKey-s1';
  int get answeredToday => today.where((q) => q.isAnswered).length;
  bool get completed => _completed;
  bool get skipped => _skipped;
  bool get canSkip => !(required && !_firstSetCompleted);

  void _fill(int count, int answered, {required int offset}) {
    today.clear();
    for (var i = 1; i <= count; i++) {
      today.add(
        learningQuestion(offset + i, answer: i <= answered ? 'a' : null),
      );
    }
  }

  /// The server's day turned: a new set, nothing answered, not skipped.
  void newDay(String next) {
    earlier.addAll(today.where((q) => q.isAnswered));
    dateKey = next;
    _fill(today.length, 0, offset: 100);
    _completed = false;
    _skipped = false;
    if (journeyStage == JourneyStage.done) {
      journeyStage = JourneyStage.daily;
    }
  }

  LearningSummary get summary => LearningSummary(
    required: required,
    blocksPicks: required && !_firstSetCompleted,
    firstSetCompleted: _firstSetCompleted,
    humorCalibrated: humorCalibrated,
    journeyStage: journeyStage,
    today: DailyProgress(
      dateKey: dateKey,
      questionSetId: questionSetId,
      total: today.length,
      answered: answeredToday,
      completed: _completed,
      skipped: _skipped,
      canSkip: canSkip,
    ),
    nextDayStartsAt: DateTime.utc(2026, 9, 29, 21),
  );

  @override
  Future<Result<RelationshipLearningState>> loadState() async {
    loads += 1;
    if (failLoads) {
      return const Err(NetworkFailure('offline'));
    }
    final answered = [...earlier, ...today.where((q) => q.isAnswered)];
    return Success(
      RelationshipLearningState(
        summary: summary,
        today: DailyQuestionSet(
          dateKey: dateKey,
          questionSetId: questionSetId,
          questions: List.of(today),
        ),
        overview: LearningOverview(
          overallProgress: answered.length / 64,
          categories: categories,
          totals: LearningTotals(
            thisMonth: thisMonth + answeredToday,
            total: answered.length,
            completedDays: completions,
          ),
          highlights: highlights,
          answered: [
            for (final q in answered) AnsweredLearningQuestion(question: q),
          ],
        ),
      ),
    );
  }

  @override
  Future<Result<DailyAnswerResult>> saveDailyAnswer({
    required String questionSetId,
    required String questionId,
    required int questionVersion,
    required String answerId,
  }) async {
    if (failSaves) {
      return const Err(UnexpectedFailure(''));
    }
    if (questionSetId != this.questionSetId) {
      return const Err(ValidationFailure(learningStaleSetReason));
    }
    final i = today.indexWhere((q) => q.id == questionId);
    if (i < 0 ||
        today[i].version != questionVersion ||
        !today[i].options.any((o) => o.id == answerId)) {
      return const Err(ValidationFailure('invalid-answer'));
    }
    saves.add((questionSetId, questionId, questionVersion, answerId));
    today[i] = today[i].withAnswer(answerId);
    var completedNow = false;
    var firstNow = false;
    if (!_completed && answeredToday == today.length) {
      _completed = true;
      completedNow = true;
      completions += 1;
      firstNow = !_firstSetCompleted;
      _firstSetCompleted = true;
      if (journeyStage == JourneyStage.daily) {
        journeyStage = JourneyStage.done;
      }
    }
    return Success(
      DailyAnswerResult(
        summary: summary,
        completedTodayNow: completedNow,
        firstSetCompletedNow: firstNow,
      ),
    );
  }

  @override
  Future<Result<void>> updateAnswer({
    required String questionId,
    required int questionVersion,
    required String answerId,
  }) async {
    if (failSaves) {
      return const Err(UnexpectedFailure(''));
    }
    updates.add((questionId, answerId));
    for (final list in [earlier, today]) {
      final i = list.indexWhere((q) => q.id == questionId && q.isAnswered);
      if (i >= 0) {
        list[i] = list[i].withAnswer(answerId);
        return const Success(null);
      }
    }
    return const Err(ValidationFailure('not-answered'));
  }

  @override
  Future<Result<LearningSummary>> skipToday() async {
    if (failSkip || !canSkip) {
      return const Err(ValidationFailure('first-set-required'));
    }
    skips += 1;
    _skipped = true;
    if (journeyStage == JourneyStage.daily) {
      journeyStage = JourneyStage.done;
    }
    return Success(summary);
  }

  @override
  Future<Result<void>> skipOnboardingHumor() async {
    humorSkips += 1;
    if (journeyStage == JourneyStage.humor) {
      journeyStage = JourneyStage.daily;
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> resetLearnedPreferences() async {
    if (failReset) {
      return const Err(NetworkFailure('offline'));
    }
    resets += 1;
    return const Success(null);
  }
}
