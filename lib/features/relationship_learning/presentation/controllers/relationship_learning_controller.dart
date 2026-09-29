import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/features/relationship_learning/data/relationship_learning_analytics.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// Which set of questions the flow is walking through.
enum LearningFlowMode {
  /// The initial questions every member answers once.
  initial,

  /// A short follow-up round, after the initial set.
  followUp,

  /// Whichever fits: the initial set while unfinished, else a follow-up round.
  auto,
}

enum LearningFlowPhase { loading, intro, question, done, nothingToAsk, error }

/// Drives one pass through relationship-learning questions.
///
/// Every answer is saved the moment it is chosen, so leaving at question 8
/// and coming back resumes at the first unanswered one. The server is the
/// source of truth: progress and completion always come from its response.
class RelationshipLearningController extends ChangeNotifier {
  RelationshipLearningController({
    required RelationshipLearningRepository repository,
    required LearningFlowMode mode,
    RelationshipLearningAnalytics? analytics,
    this.source = 'unknown',
  }) : _repository = repository,
       _mode = mode,
       _analytics = analytics ?? const RelationshipLearningAnalytics(null);

  final RelationshipLearningRepository _repository;
  final RelationshipLearningAnalytics _analytics;
  LearningFlowMode _mode;

  /// The resolved mode ([LearningFlowMode.auto] is decided on load).
  LearningFlowMode get mode => _mode;

  /// Where the flow was opened from, for analytics only.
  final String source;

  LearningFlowPhase _phase = LearningFlowPhase.loading;
  List<LearningQuestion> _questions = const [];
  int _index = 0;
  bool _saving = false;
  bool _disposed = false;
  String? _loadError;
  String? _actionError;
  LearningSummary _summary = LearningSummary.unknown;
  bool _completedInitialNow = false;

  LearningFlowPhase get phase => _phase;
  List<LearningQuestion> get questions => _questions;
  int get index => _index;
  int get total => _questions.length;
  bool get saving => _saving;
  String? get loadError => _loadError;
  LearningSummary get summary => _summary;
  bool get completedInitialNow => _completedInitialNow;
  bool get isFollowUp => _mode == LearningFlowMode.followUp;

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
        if (_mode == LearningFlowMode.auto) {
          _mode = state.summary.initialCompleted
              ? LearningFlowMode.followUp
              : LearningFlowMode.initial;
        }
        _questions = isFollowUp
            ? state.followUpQuestions
            : state.initialQuestions;
        if (_questions.isEmpty) {
          _phase = LearningFlowPhase.nothingToAsk;
          return;
        }
        if (!isFollowUp && state.summary.initialCompleted) {
          _phase = LearningFlowPhase.done;
          return;
        }
        final firstOpen = _questions.indexWhere((q) => !q.isAnswered);
        if (firstOpen < 0) {
          // Every question answered but the round is not closed yet: show the
          // last one so a single tap finishes it.
          _index = _questions.length - 1;
          _phase = LearningFlowPhase.question;
          return;
        }
        _index = firstOpen;
        // A fresh start gets the short introduction; a resume goes straight
        // back to the question the member stopped at.
        final fresh = answeredCount == 0 && !isFollowUp;
        _phase = fresh ? LearningFlowPhase.intro : LearningFlowPhase.question;
        if (!fresh) {
          _analytics.started(followUp: isFollowUp, source: source);
        }
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
    _analytics.started(followUp: isFollowUp, source: source);
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
  /// previous answer and leaves the member on the same question.
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

    final result = await _repository.saveAnswer(
      questionId: question.id,
      answerId: answerId,
    );
    if (_disposed) {
      return;
    }
    _saving = false;
    result.when(
      success: (saved) {
        _summary = saved.summary;
        _analytics.answered(
          followUp: isFollowUp,
          dimension: question.dimension,
          position: position + 1,
        );
        if (saved.completedInitialNow) {
          _completedInitialNow = true;
          _analytics.initialCompleted();
        }
        if (saved.completedRoundNow) {
          _analytics.followUpCompleted();
        }
        _advanceFrom(position);
      },
      err: (failure) {
        _replace(position, question.withAnswer(previous));
        _actionError = failure.message.isEmpty ? '' : failure.message;
      },
    );
    _notify();
  }

  void _advanceFrom(int position) {
    final nextOpen = _questions.indexWhere((q) => !q.isAnswered);
    final finished = isFollowUp
        ? nextOpen < 0
        : _summary.initialCompleted || nextOpen < 0;
    if (finished) {
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

/// Unawaited helper for fire-and-forget snoozes from cards.
Future<void> snoozeFollowUpQuietly(
  RelationshipLearningRepository repository,
  RelationshipLearningAnalytics analytics,
) async {
  analytics.followUpSnoozed();
  await repository.snoozeFollowUp();
}
