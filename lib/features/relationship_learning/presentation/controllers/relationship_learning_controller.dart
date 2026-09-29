import 'package:flutter/foundation.dart';
import 'package:mevora/features/relationship_learning/data/relationship_learning_analytics.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

enum LearningFlowPhase { loading, intro, question, done, skipped, error }

/// Drives today's 10 relationship questions.
///
/// The set, its order and the day come from the server. Every answer is
/// saved the moment it is chosen, so leaving at question 4 and coming back
/// (even after a restart) resumes at the first unanswered one. Completion
/// always comes from the server's response, never from local counting.
class RelationshipLearningController extends ChangeNotifier {
  RelationshipLearningController({
    required RelationshipLearningRepository repository,
    RelationshipLearningAnalytics? analytics,
    this.source = 'unknown',
  }) : _repository = repository,
       _analytics = analytics ?? const RelationshipLearningAnalytics(null);

  final RelationshipLearningRepository _repository;
  final RelationshipLearningAnalytics _analytics;

  /// Where the flow was opened from, for analytics only.
  final String source;

  LearningFlowPhase _phase = LearningFlowPhase.loading;
  DailyQuestionSet _set = DailyQuestionSet.empty;
  List<LearningQuestion> _questions = const [];
  int _index = 0;
  bool _saving = false;
  bool _disposed = false;
  String? _loadError;
  String? _actionError;
  LearningSummary _summary = LearningSummary.unknown;
  bool _completedNow = false;

  LearningFlowPhase get phase => _phase;
  List<LearningQuestion> get questions => _questions;
  String get questionSetId => _set.questionSetId;
  int get index => _index;
  int get total => _questions.length;
  bool get saving => _saving;
  String? get loadError => _loadError;
  LearningSummary get summary => _summary;

  /// Today's set was finished in this session (not just found finished).
  bool get completedNow => _completedNow;

  /// "Bugünlük geç" is available: never for a new member's first set.
  bool get canSkip =>
      _summary.today.canSkip &&
      (_phase == LearningFlowPhase.intro ||
          _phase == LearningFlowPhase.question);

  LearningQuestion? get current =>
      _index >= 0 && _index < _questions.length ? _questions[_index] : null;

  int get answeredCount => _questions.where((q) => q.isAnswered).length;

  bool get canGoBack => _phase == LearningFlowPhase.question && _index > 0;

  bool get canGoForward =>
      _phase == LearningFlowPhase.question &&
      (current?.isAnswered ?? false) &&
      _index < _questions.length - 1;

  /// Takes the pending action error, once.
  String? takeActionError() {
    final error = _actionError;
    _actionError = null;
    return error;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    _phase = LearningFlowPhase.loading;
    _loadError = null;
    _notify();
    final result = await _repository.loadState();
    if (_disposed) {
      return;
    }
    result.when(
      success: (state) {
        _summary = state.summary;
        _set = state.today;
        _questions = List.unmodifiable(state.today.questions);
        if (_questions.isEmpty) {
          _loadError = '';
          _phase = LearningFlowPhase.error;
          return;
        }
        if (state.summary.today.completed) {
          // Answered once today already: the set is not shown again.
          _phase = LearningFlowPhase.done;
          return;
        }
        final firstOpen = _questions.indexWhere((q) => !q.isAnswered);
        _index = firstOpen < 0 ? _questions.length - 1 : firstOpen;
        if (answeredCount == 0) {
          _phase = LearningFlowPhase.intro;
          return;
        }
        // A resume goes straight back to the question the member stopped at.
        _phase = LearningFlowPhase.question;
        _analytics.resumed(
          questionSetId: questionSetId,
          source: source,
          answered: answeredCount,
        );
      },
      err: (failure) {
        _loadError = failure.message;
        _phase = LearningFlowPhase.error;
      },
    );
    _notify();
  }

  void begin() {
    if (_phase != LearningFlowPhase.intro) {
      return;
    }
    _analytics.shown(questionSetId: questionSetId, source: source);
    _phase = LearningFlowPhase.question;
    _notify();
  }

  void back() {
    if (!canGoBack || _saving) {
      return;
    }
    _index -= 1;
    _notify();
  }

  void forward() {
    if (!canGoForward || _saving) {
      return;
    }
    _index += 1;
    _notify();
  }

  /// Saves the chosen option, then moves on. A failed save restores the
  /// previous answer and leaves the member on the same question. If the day
  /// turned while answering, today's new set is loaded instead.
  Future<void> choose(String answerId) async {
    final question = current;
    if (question == null || _saving || _phase != LearningFlowPhase.question) {
      return;
    }
    final position = _index;
    final previous = question.answerId;
    _replace(position, question.withAnswer(answerId));
    _saving = true;
    _notify();

    final result = await _repository.saveDailyAnswer(
      questionSetId: questionSetId,
      questionId: question.id,
      questionVersion: question.version,
      answerId: answerId,
    );
    if (_disposed) {
      return;
    }
    _saving = false;
    var stale = false;
    result.when(
      success: (saved) {
        _summary = saved.summary;
        _analytics.answered(
          questionSetId: questionSetId,
          category: question.category,
          position: position + 1,
        );
        if (saved.completedTodayNow) {
          _completedNow = true;
          _analytics.completed(
            questionSetId: questionSetId,
            firstSet: saved.firstSetCompletedNow,
          );
        }
        _advanceFrom(position);
      },
      err: (failure) {
        _replace(position, question.withAnswer(previous));
        stale = failure.message == learningStaleSetReason;
        _actionError = stale ? null : failure.message;
      },
    );
    _notify();
    if (stale) {
      await load();
    }
  }

  /// "Bugünlük geç": puts today's set away until tomorrow. Resolves true
  /// when the server recorded it.
  Future<bool> skipToday() async {
    if (!canSkip || _saving) {
      return false;
    }
    _saving = true;
    _notify();
    final result = await _repository.skipToday();
    if (_disposed) {
      return false;
    }
    _saving = false;
    var ok = false;
    result.when(
      success: (summary) {
        ok = true;
        _analytics.skipped(
          questionSetId: questionSetId,
          source: source,
          answered: answeredCount,
        );
        _summary = summary;
        _phase = LearningFlowPhase.skipped;
      },
      err: (failure) => _actionError = failure.message,
    );
    _notify();
    return ok;
  }

  void _advanceFrom(int position) {
    final nextOpen = _questions.indexWhere((q) => !q.isAnswered);
    if (_summary.today.completed || nextOpen < 0) {
      _phase = LearningFlowPhase.done;
      return;
    }
    // Changing an earlier answer steps forward one; otherwise continue with
    // the first question still open.
    _index =
        position < _questions.length - 1 && _questions[position + 1].isAnswered
        ? position + 1
        : nextOpen;
  }

  void _replace(int position, LearningQuestion question) {
    final next = [..._questions];
    next[position] = question;
    _questions = List.unmodifiable(next);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
