import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// A question as the server would send it.
LearningQuestion learningQuestion(int n, {String? answer, String? dimension}) {
  return LearningQuestion(
    id: 'rl_q$n',
    version: 1,
    kind: LearningQuestionKind.stance,
    dimension: dimension ?? 'values',
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

/// Behaves like the server: validates, stores, completes exactly once.
class FakeRelationshipLearningRepository
    implements RelationshipLearningRepository {
  FakeRelationshipLearningRepository({
    int initialCount = 15,
    int answered = 0,
    List<LearningQuestion>? followUp,
    this.required = false,
  }) {
    for (var i = 1; i <= initialCount; i++) {
      initial.add(learningQuestion(i, answer: i <= answered ? 'a' : null));
    }
    this.followUp = followUp ?? const [];
  }

  final List<LearningQuestion> initial = [];
  late List<LearningQuestion> followUp;
  final bool required;
  final List<(String, String)> saves = [];
  int loads = 0;
  int snoozes = 0;
  int resets = 0;
  int completions = 0;
  bool failSaves = false;
  bool failLoads = false;
  bool failReset = false;
  bool _completed = false;

  int get answeredInitial => initial.where((q) => q.isAnswered).length;

  LearningSummary get summary => LearningSummary(
    required: required,
    initialTotal: initial.length,
    initialAnswered: answeredInitial,
    initialCompleted: _completed || answeredInitial == initial.length,
    blocksPicks: required && !(_completed || answeredInitial == initial.length),
  );

  @override
  Future<Result<RelationshipLearningState>> loadState() async {
    loads += 1;
    if (failLoads) {
      return const Err(NetworkFailure('offline'));
    }
    return Success(
      RelationshipLearningState(
        summary: summary,
        initialQuestions: List.of(initial),
        followUpQuestions: summary.initialCompleted ? List.of(followUp) : [],
      ),
    );
  }

  @override
  Future<Result<LearningAnswerResult>> saveAnswer({
    required String questionId,
    required String answerId,
  }) async {
    if (failSaves) {
      return const Err(NetworkFailure(''));
    }
    saves.add((questionId, answerId));
    var completedNow = false;
    var roundNow = false;
    final i = initial.indexWhere((q) => q.id == questionId);
    if (i >= 0) {
      initial[i] = initial[i].withAnswer(answerId);
      if (!_completed && answeredInitial == initial.length) {
        _completed = true;
        completedNow = true;
        completions += 1;
      }
    }
    final f = followUp.indexWhere((q) => q.id == questionId);
    if (f >= 0) {
      followUp = [...followUp]..[f] = followUp[f].withAnswer(answerId);
      roundNow = followUp.every((q) => q.isAnswered);
    }
    return Success(
      LearningAnswerResult(
        summary: summary,
        completedInitialNow: completedNow,
        completedRoundNow: roundNow,
      ),
    );
  }

  @override
  Future<Result<void>> snoozeFollowUp() async {
    snoozes += 1;
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
