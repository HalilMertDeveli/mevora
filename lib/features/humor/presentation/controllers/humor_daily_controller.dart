import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';

class HumorDailyViewState {
  const HumorDailyViewState({
    this.set,
    this.currentIndex = 0,
    this.isLoading = false,
    this.isSubmitting = false,
    this.failure,
    this.actionFailure,
    this.actionFailureId = 0,
  });

  /// Today's set as the server last described it. `null` before the first
  /// successful load.
  final HumorDailySet? set;

  /// Slot on screen. Always the server's `nextIndex`: the client never moves
  /// on before the server has confirmed the answer.
  final int currentIndex;
  final bool isLoading;

  /// An answer is in flight; the rating bar is disabled until it settles.
  final bool isSubmitting;

  /// A failed load, shown full screen.
  final Failure? failure;

  /// The latest failed answer. [actionFailureId] changes once per failure so
  /// the page reports each one exactly once.
  final Failure? actionFailure;
  final int actionFailureId;

  bool get isReady => set?.isReady == true;
  bool get completed => isReady && set!.completed;
  int get total => set?.total ?? 0;

  /// 1-based position of the item on screen ("4/10").
  int get position => currentIndex + 1;

  HumorContent? get current {
    final daily = set;
    if (daily == null || !daily.isReady || daily.completed) {
      return null;
    }
    if (currentIndex < 0 || currentIndex >= daily.items.length) {
      return null;
    }
    return daily.items[currentIndex];
  }

  /// A rating or media-failed skip would be accepted right now.
  bool get canAct => current != null && !isLoading && !isSubmitting;

  HumorDailyViewState copyWith({
    HumorDailySet? set,
    int? currentIndex,
    bool? isLoading,
    bool? isSubmitting,
    Failure? failure,
    bool clearFailure = false,
    Failure? actionFailure,
    int? actionFailureId,
  }) {
    return HumorDailyViewState(
      set: set ?? this.set,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      actionFailure: actionFailure ?? this.actionFailure,
      actionFailureId: actionFailureId ?? this.actionFailureId,
    );
  }
}

/// Plays today's "Bugünün Mizah Turu": loads the server's set, resumes at its
/// `nextIndex`, submits one answer at a time and reloads whenever the server
/// says the day, slot or eligibility changed underneath.
class HumorDailyController extends ChangeNotifier {
  HumorDailyController({required HumorRepository repository, this.analytics})
    : _repository = repository;

  /// Analytics `reason` for a slot passed because its media failed.
  static const playbackFailedReason = 'media_failed';

  final HumorRepository _repository;
  final AnalyticsProvider? analytics;

  HumorDailyViewState _state = const HumorDailyViewState(isLoading: true);
  HumorDailyViewState get state => _state;

  /// Guards against a second submission while one is in flight. Kept outside
  /// the state so a reload cannot reset it under a running request.
  var _submitting = false;
  var _generation = 0;
  var _disposed = false;
  Future<void> Function()? _retry;

  /// The day whose start (or resume) has been logged, so it is logged once.
  String? _entryLoggedDay;
  final Set<String> _playbackFailureLogged = <String>{};
  final Map<String, DateTime> _viewStartedAt = {};

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _log(String name, Map<String, Object> parameters) {
    final provider = analytics;
    if (provider == null) {
      return;
    }
    unawaited(provider.logEvent(name, parameters: parameters));
  }

  Future<void> load() async {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    _retry = null;
    _state = _state.copyWith(isLoading: true, clearFailure: true);
    notifyListeners();

    final result = await _repository.getDailySet();
    if (_disposed || generation != _generation) {
      return;
    }
    result.when(
      success: (set) {
        _state = HumorDailyViewState(
          set: set,
          currentIndex: set.nextIndex,
          actionFailure: _state.actionFailure,
          actionFailureId: _state.actionFailureId,
        );
        _logEntry(set);
        _markViewed(_state.current);
      },
      err: (failure) {
        _state = _state.copyWith(isLoading: false, failure: failure);
      },
    );
    notifyListeners();
  }

  /// Rate the item on screen. Ignored while another answer is in flight.
  Future<void> rate(HumorRating rating) async {
    final item = _state.current;
    final set = _state.set;
    if (item == null || set == null || !_state.canAct || _submitting) {
      return;
    }
    final contentId = item.contentId;
    _beginSubmit();
    final result = await _repository.submitDailyResponse(
      dayId: set.dayId,
      contentId: contentId,
      rating: rating,
      dwellMs: _dwellMs(contentId),
    );
    await _settle(result, retry: () => _retryOn(contentId, () => rate(rating)));
  }

  /// "Next" on an item whose media could not be played: the server records a
  /// `media_failed` skip for that slot. Ignored unless [contentId] is the item
  /// on screen, so a late tap never passes a different slot.
  Future<void> skipUnplayable(String contentId) async {
    final item = _state.current;
    final set = _state.set;
    if (item == null ||
        set == null ||
        item.contentId != contentId ||
        !_state.canAct ||
        _submitting) {
      return;
    }
    if (_playbackFailureLogged.add(contentId)) {
      _log(AnalyticsEvents.dailyHumorPlaybackFailed, {
        'position': _state.position,
        'reason': playbackFailedReason,
      });
    }
    _beginSubmit();
    final result = await _repository.skipDailyItem(
      dayId: set.dayId,
      contentId: contentId,
    );
    await _settle(
      result,
      retry: () => _retryOn(contentId, () => skipUnplayable(contentId)),
    );
  }

  /// Run the answer that failed last, once. The server treats a repeat of an
  /// answer that did land as a no-op, so a retry never counts twice.
  Future<void> retryFailedAction() async {
    final retry = _retry;
    _retry = null;
    if (retry == null || _disposed) {
      return;
    }
    await retry();
  }

  void _beginSubmit() {
    _submitting = true;
    _retry = null;
    _state = _state.copyWith(isSubmitting: true);
    notifyListeners();
  }

  Future<void> _settle(
    Result<HumorDailySubmitOutcome> result, {
    required Future<void> Function() retry,
  }) async {
    _submitting = false;
    if (_disposed) {
      return;
    }
    final outcome = result.valueOrNull;
    if (outcome == null) {
      // Network or other failure: keep the item on screen and offer a retry.
      _retry = retry;
      _state = _state.copyWith(
        isSubmitting: false,
        actionFailure: result.failureOrNull,
        actionFailureId: _state.actionFailureId + 1,
      );
      notifyListeners();
      return;
    }
    switch (outcome) {
      case HumorDailyAccepted(:final progress):
        final set = _state.set;
        if (set == null ||
            (progress.dayId.isNotEmpty && progress.dayId != set.dayId)) {
          await load();
          return;
        }
        _applyProgress(set, progress);
      case HumorDailyStale():
        // The day rolled over, the slot changed or the user is no longer
        // eligible: the server's picture wins, so start again from it.
        _state = _state.copyWith(isSubmitting: false);
        await load();
    }
  }

  void _applyProgress(HumorDailySet set, HumorDailyProgress progress) {
    final next = set.withProgress(progress);
    _state = _state.copyWith(
      set: next,
      currentIndex: next.nextIndex,
      isSubmitting: false,
    );
    if (!progress.alreadyAnswered) {
      _log(AnalyticsEvents.dailyHumorProgress, {
        'position': next.answeredCount,
        'total': next.total,
      });
    }
    if (next.completed && !set.completed) {
      _log(AnalyticsEvents.dailyHumorCompleted, {'total': next.total});
    }
    notifyListeners();
    _markViewed(_state.current);
  }

  Future<void> _retryOn(String contentId, Future<void> Function() action) {
    if (_state.current?.contentId != contentId) {
      return Future<void>.value();
    }
    return action();
  }

  void _logEntry(HumorDailySet set) {
    if (!set.isReady || set.completed || _entryLoggedDay == set.dayId) {
      return;
    }
    _entryLoggedDay = set.dayId;
    if (set.answeredCount == 0) {
      _log(AnalyticsEvents.dailyHumorStarted, {'position': 1});
    } else {
      _log(AnalyticsEvents.dailyHumorResume, {'position': set.nextIndex + 1});
    }
  }

  void _markViewed(HumorContent? item) {
    if (item == null) {
      return;
    }
    _viewStartedAt[item.contentId] = DateTime.now();
  }

  int _dwellMs(String contentId) {
    final started = _viewStartedAt[contentId];
    if (started == null) {
      return 0;
    }
    return DateTime.now().difference(started).inMilliseconds.clamp(0, 120000);
  }
}
