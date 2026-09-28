import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';

/// The card the user can step back to with "previous item".
class _BackEntry {
  const _BackEntry({required this.index, required this.contentId});

  final int index;
  final String contentId;
}

class HumorViewState {
  const HumorViewState({
    this.items = const [],
    this.currentIndex = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSubmitting = false,
    this.failure,
    this.actionFailure,
    this.actionFailureId = 0,
    this.profile = UserHumorProfile.empty,
    this.nextCursor,
    this.lastRated,
    this.replayToken = 0,
    this.canGoBack = false,
    this.calibration = HumorCalibration.empty,
    this.calibrationJustCompleted = false,
    this.catalogExhausted = false,
    this.catalogEmpty = false,
    this.reachedEnd = false,
    this.loadMoreFailed = false,
  });

  final List<HumorContent> items;

  /// Index of the card on screen. It equals `items.length` once the user has
  /// passed the last loaded card: the next page is loading, failed, or there
  /// is nothing more ([reachedEnd]).
  final int currentIndex;
  final bool isLoading;
  final bool isLoadingMore;

  /// A rating, skip or report is in flight. Nothing else may be submitted
  /// until it settles — a double tap must never move two cards.
  final bool isSubmitting;

  /// A failed initial load. Shown full screen only while nothing is loaded.
  final Failure? failure;

  /// The latest failed action while cards are on screen (rating, skip,
  /// report, loading more). [actionFailureId] changes once per failure so the
  /// page reports each one exactly once.
  final Failure? actionFailure;
  final int actionFailureId;
  final UserHumorProfile profile;
  final String? nextCursor;

  /// The rating the user has given the card on screen, if any. `null` on a
  /// card they have not rated.
  final HumorRating? lastRated;
  final int replayToken;

  /// "Previous item" is available: the last card rated or skipped can be
  /// shown again with its current rating selected, and re-rating it replaces
  /// that rating server-side.
  final bool canGoBack;

  /// Server-reported initial calibration progress. The controller never
  /// advances this itself — it only mirrors what the backend returned.
  final HumorCalibration calibration;

  /// One-shot: the server reported the incomplete → complete transition on
  /// the rating just submitted. Never set by a load, so opening the Lab as an
  /// already calibrated user never counts as finishing calibration.
  final bool calibrationJustCompleted;

  /// The user has rated everything currently in the catalog. A finished state,
  /// not a failure — the difference decides what we say to them.
  final bool catalogExhausted;

  /// Nothing servable exists at all: an operational problem, not the user
  /// running out of content, and it must not be phrased as their doing.
  final bool catalogEmpty;

  /// The user passed the last loaded card and the server had nothing more.
  final bool reachedEnd;

  /// Loading the next page failed while the user was waiting for it.
  final bool loadMoreFailed;

  bool get isEmpty => !isLoading && failure == null && items.isEmpty;
  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  /// True while the user is still working through the structured 15.
  bool get isCalibrating => !calibration.complete;

  /// The user is past the last loaded card (waiting, failed or at the end).
  bool get atTail => items.isNotEmpty && currentIndex >= items.length;

  /// Stage of the card currently on screen, when it is a calibration item.
  HumorCalibrationStage? get currentStage => current?.calibrationStage;

  /// A rating, skip or report would be accepted right now.
  bool get canAct => current != null && !isLoading && !isSubmitting;

  HumorContent? get current {
    if (currentIndex < 0 || currentIndex >= items.length) {
      return null;
    }
    return items[currentIndex];
  }

  HumorViewState copyWith({
    List<HumorContent>? items,
    int? currentIndex,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSubmitting,
    Failure? failure,
    bool clearFailure = false,
    Failure? actionFailure,
    int? actionFailureId,
    UserHumorProfile? profile,
    String? nextCursor,
    bool clearCursor = false,
    HumorRating? lastRated,
    bool clearLastRated = false,
    int? replayToken,
    bool? canGoBack,
    HumorCalibration? calibration,
    bool? calibrationJustCompleted,
    bool? catalogExhausted,
    bool? catalogEmpty,
    bool? reachedEnd,
    bool? loadMoreFailed,
  }) {
    return HumorViewState(
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      actionFailure: actionFailure ?? this.actionFailure,
      actionFailureId: actionFailureId ?? this.actionFailureId,
      profile: profile ?? this.profile,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      lastRated: clearLastRated ? null : (lastRated ?? this.lastRated),
      replayToken: replayToken ?? this.replayToken,
      canGoBack: canGoBack ?? this.canGoBack,
      calibration: calibration ?? this.calibration,
      calibrationJustCompleted:
          calibrationJustCompleted ?? this.calibrationJustCompleted,
      catalogExhausted: catalogExhausted ?? this.catalogExhausted,
      catalogEmpty: catalogEmpty ?? this.catalogEmpty,
      reachedEnd: reachedEnd ?? this.reachedEnd,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    );
  }
}

class HumorController extends ChangeNotifier {
  HumorController({
    required HumorRepository repository,
    this.analytics,
    List<String>? languages,
  }) : _repository = repository,
       _languages = languages;

  /// How many empty pages that still carry a cursor are followed before the
  /// feed is treated as having nothing more right now.
  static const int maxEmptyPageHops = 3;

  final HumorRepository _repository;
  final AnalyticsProvider? analytics;
  final List<String>? _languages;

  HumorViewState _state = const HumorViewState(isLoading: true);
  _BackEntry? _back;

  /// Ratings given in this session, so a card shown again (previous item)
  /// shows the rating it currently holds.
  final Map<String, HumorRating> _ratings = {};
  final Map<String, int> _replayCounts = {};
  final Map<String, DateTime> _viewStartedAt = {};

  /// Guards against a second submission while one is in flight. Kept outside
  /// the state so a reload cannot reset it under a running request.
  var _submitting = false;
  Future<void>? _fetchInFlight;

  /// Bumped by [load]; results of requests started before it are dropped.
  var _generation = 0;
  Future<void> Function()? _retry;
  var _openedLogged = false;
  var _disposed = false;

  HumorViewState get state => _state;

  @override
  void notifyListeners() {
    // Requests outlive the page: the Lab is left mid-request, and on the
    // fifteenth rating it navigates away while work is still settling.
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

  void _log(String name, {Map<String, Object>? parameters}) {
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
    _state = _state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearFailure: true,
      reachedEnd: false,
      loadMoreFailed: false,
      calibrationJustCompleted: false,
    );
    notifyListeners();
    if (!_openedLogged) {
      _openedLogged = true;
      _log(AnalyticsEvents.humorLabOpened);
    }

    final feed = await _fetchPage(cursor: null);
    if (_disposed || generation != _generation) {
      return;
    }
    if (feed.isError) {
      _state = _state.copyWith(
        isLoading: false,
        failure: feed.failureOrNull,
        items: const [],
        currentIndex: 0,
        clearCursor: true,
        canGoBack: false,
        clearLastRated: true,
      );
      notifyListeners();
      return;
    }

    final page = feed.valueOrNull!;
    _back = null;
    _ratings.clear();
    // Calibration analytics are deliberately not emitted here: loading only
    // restores where the user is. Progress and completion are logged from the
    // ratings that cause them, and "started" from the intro's Start button.
    _state = _state.copyWith(
      items: page.items,
      currentIndex: 0,
      isLoading: false,
      profile: _state.profile.copyWith(
        interactionCount: page.interactionCount,
        profileBuilding: page.profileBuilding,
        calibration: page.calibration,
      ),
      nextCursor: page.nextCursor,
      clearCursor: !page.hasMore,
      clearLastRated: true,
      canGoBack: false,
      calibration: page.calibration,
      catalogExhausted: page.catalogExhausted,
      catalogEmpty: page.catalogEmpty,
      reachedEnd: false,
      loadMoreFailed: false,
    );
    notifyListeners();
    _markViewed(page.items.isEmpty ? null : page.items.first);
    await _refreshProfile();
  }

  /// Fetch the next page for a user waiting at the end of the loaded list —
  /// after a failure, from the "nothing more" state, or once calibration has
  /// been handed off. Only one feed request is ever in flight.
  Future<void> loadMore() async {
    if (_disposed || _state.isLoading) {
      return;
    }
    await _fetchMore();
  }

  /// Merge calibration progress that arrived from a non-feed response.
  ///
  /// Only `getHumorFeed` runs pool selection, so only it knows whether the
  /// curated pool could fill the remaining positions. The feedback and profile
  /// payloads carry progress but default `insufficientPool` to false — taking
  /// them verbatim would silently erase a catalog-deficiency signal.
  HumorCalibration _withPoolFlag(HumorCalibration next) {
    return next.copyWith(insufficientPool: _state.calibration.insufficientPool);
  }

  /// Emit calibration analytics for a rating's server-reported effect only.
  ///
  /// Deliberately carries stage and counts and nothing else — the humor vector
  /// is behavioural data and never leaves the device through analytics.
  void _logCalibration({
    required HumorCalibration previous,
    required HumorCalibration next,
  }) {
    if (next.complete && !previous.complete) {
      _log(
        AnalyticsEvents.humorCalibrationCompleted,
        parameters: {'version': next.version, 'total': next.totalCount},
      );
      return;
    }
    if (!next.complete && next.completedCount != previous.completedCount) {
      _log(
        AnalyticsEvents.humorCalibrationProgress,
        parameters: {
          'version': next.version,
          'stage': HumorCalibration.stageValue(next.stage),
          'completed': next.completedCount,
          'total': next.totalCount,
        },
      );
    }
  }

  /// The page hands the user to the result screen; this acknowledges it.
  void consumeCalibrationCompleted() {
    if (!_state.calibrationJustCompleted) {
      return;
    }
    _state = _state.copyWith(calibrationJustCompleted: false);
  }

  Future<void> onPageChanged(int index) async {
    if (index < 0 || index >= _state.items.length || _disposed) {
      return;
    }
    final item = _state.items[index];
    _state = _withCurrent(index);
    notifyListeners();
    _markViewed(item);
    await _maybePrefetch();
  }

  Future<void> rate(
    HumorRating rating, {
    bool? swipeUp,
    bool? swipeDown,
  }) async {
    final item = _state.current;
    if (item == null || !_state.canAct || _submitting) {
      return;
    }
    final contentId = item.contentId;
    final index = _state.currentIndex;
    _beginSubmit();

    final result = await _repository.submitFeedback(
      contentId: contentId,
      rating: rating,
      dwellMs: _dwellMs(contentId),
      replayCount: _replayCounts[contentId] ?? 0,
      swipeUp: swipeUp,
      swipeDown: swipeDown,
    );
    _submitting = false;
    if (_disposed) {
      return;
    }

    var justCompleted = false;
    result.when(
      success: (feedback) {
        _ratings[contentId] = rating;
        _back = _BackEntry(index: index, contentId: contentId);
        final previousCalibration = _state.calibration;
        final nextCalibration = _withPoolFlag(feedback.calibration);
        justCompleted =
            nextCalibration.complete && !previousCalibration.complete;
        _state = _state.copyWith(
          isSubmitting: false,
          canGoBack: true,
          lastRated: _isCurrent(index, contentId) ? rating : null,
          profile: _state.profile.copyWith(
            interactionCount: feedback.interactionCount,
            profileBuilding: feedback.profileBuilding,
            confidence: feedback.confidence,
            calibration: nextCalibration,
          ),
          calibration: nextCalibration,
          calibrationJustCompleted: justCompleted ? true : null,
        );
        _logCalibration(previous: previousCalibration, next: nextCalibration);
        _log(
          AnalyticsEvents.humorContentRated,
          parameters: {'content_id': contentId, 'rating': rating.apiValue},
        );
      },
      err: (failure) {
        _state = _state.copyWith(isSubmitting: false);
        _reportActionFailure(
          failure,
          retry: () => _retryOn(
            contentId,
            () => rate(rating, swipeUp: swipeUp, swipeDown: swipeDown),
          ),
        );
      },
    );
    notifyListeners();

    if (result.isSuccess) {
      // Calibration just finished: the page is about to show the result, so
      // fetching (and consuming) another page now would only waste it.
      await _advanceFrom(index, contentId, fetchAtTail: !justCompleted);
    }
  }

  /// Move past the card on screen without rating it.
  Future<void> skip() => _skip();

  /// Move past [contentId], whose media could not be played, without rating
  /// it. The server records it as a `media_failed` skip: never a rating,
  /// never part of calibration, and the item is not served to this user again
  /// — calibration then hands out a replacement through the usual tail fetch.
  ///
  /// Ignored unless [contentId] is the card on screen, so a late tap from a
  /// card that has already scrolled away can never skip a different item.
  Future<void> skipUnplayable(String contentId) {
    if (_state.current?.contentId != contentId) {
      return Future<void>.value();
    }
    return _skip(skipReason: HumorSkipReason.mediaFailed);
  }

  Future<void> _skip({String? skipReason}) async {
    final item = _state.current;
    if (item == null || !_state.canAct || _submitting) {
      return;
    }
    final contentId = item.contentId;
    final index = _state.currentIndex;
    _beginSubmit();

    final result = await _repository.skipContent(
      contentId: contentId,
      skipReason: skipReason,
    );
    _submitting = false;
    if (_disposed) {
      return;
    }
    result.when(
      success: (feedback) {
        _back = _BackEntry(index: index, contentId: contentId);
        _state = _state.copyWith(
          isSubmitting: false,
          canGoBack: true,
          calibration: _withPoolFlag(feedback.calibration),
        );
        if (skipReason == HumorSkipReason.mediaFailed) {
          _log(
            AnalyticsEvents.humorMediaSkipped,
            parameters: {
              'content_id': contentId,
              'reason': HumorSkipReason.mediaFailed,
            },
          );
        } else {
          _log(
            AnalyticsEvents.humorContentSkipped,
            parameters: {'content_id': contentId},
          );
        }
      },
      err: (failure) {
        _state = _state.copyWith(isSubmitting: false);
        _reportActionFailure(
          failure,
          retry: () => _retryOn(contentId, () => _skip(skipReason: skipReason)),
        );
      },
    );
    notifyListeners();
    if (result.isSuccess) {
      await _advanceFrom(index, contentId, fetchAtTail: true);
    }
  }

  /// Report the card on screen. On success the reporter moves past it and is
  /// never shown it again; no rating is recorded.
  Future<Result<void>?> reportCurrent(String reason) async {
    final item = _state.current;
    if (item == null || !_state.canAct || _submitting) {
      return null;
    }
    final contentId = item.contentId;
    final index = _state.currentIndex;
    _beginSubmit();

    final result = await _repository.reportContent(
      contentId: contentId,
      reason: reason,
    );
    _submitting = false;
    if (_disposed) {
      return result;
    }
    result.when(
      success: (_) {
        // Nothing to step back to: the reported card must not come back.
        _back = null;
        _state = _state.copyWith(isSubmitting: false, canGoBack: false);
      },
      err: (failure) {
        _state = _state.copyWith(isSubmitting: false);
        _reportActionFailure(
          failure,
          retry: () => _retryOn(contentId, () => reportCurrent(reason)),
        );
      },
    );
    notifyListeners();
    if (result.isSuccess) {
      await _advanceFrom(index, contentId, fetchAtTail: true);
    }
    return result;
  }

  Future<void> rateSwipeUp() => rate(HumorRating.funny, swipeUp: true);

  Future<void> rateSwipeDown() => rate(HumorRating.notFunny, swipeDown: true);

  /// Show the previous card again, with the rating it currently holds
  /// selected. Rating it again replaces that rating on the server.
  void goBack() {
    final entry = _back;
    if (entry == null || _submitting || _state.isLoading || _disposed) {
      return;
    }
    _back = null;
    final items = _state.items;
    if (entry.index >= items.length ||
        items[entry.index].contentId != entry.contentId) {
      _state = _state.copyWith(canGoBack: false);
      notifyListeners();
      return;
    }
    _state = _withCurrent(
      entry.index,
    ).copyWith(canGoBack: false, reachedEnd: false, loadMoreFailed: false);
    notifyListeners();
    _markViewed(items[entry.index]);
  }

  /// Run the action that failed last, once. A rating is re-sent as the same
  /// rating, which the server treats as a no-op if the first attempt landed,
  /// so a retry never counts twice.
  Future<void> retryFailedAction() async {
    final retry = _retry;
    _retry = null;
    if (retry == null || _disposed) {
      return;
    }
    await retry();
  }

  void replayCurrent() {
    final item = _state.current;
    if (item == null) {
      return;
    }
    _replayCounts[item.contentId] = (_replayCounts[item.contentId] ?? 0) + 1;
    _state = _state.copyWith(replayToken: _state.replayToken + 1);
    notifyListeners();
    _log(
      AnalyticsEvents.humorContentReplayed,
      parameters: {'content_id': item.contentId},
    );
  }

  Future<void> refreshProfile({bool detailed = true}) async {
    await _refreshProfile(detailed: detailed);
    _log(AnalyticsEvents.humorProfileViewed);
  }

  Future<void> _refreshProfile({bool detailed = false}) async {
    final result = await _repository.getProfile(detailed: detailed);
    if (_disposed) {
      return;
    }
    result.when(
      success: (profile) {
        _state = _state.copyWith(
          profile: profile,
          calibration: _withPoolFlag(profile.calibration),
        );
      },
      err: (_) {},
    );
    notifyListeners();
  }

  void _beginSubmit() {
    _submitting = true;
    _retry = null;
    _state = _state.copyWith(isSubmitting: true);
    notifyListeners();
  }

  bool _isCurrent(int index, String contentId) =>
      _state.currentIndex == index && _state.current?.contentId == contentId;

  /// Re-run [action] only if the card it failed on is still on screen.
  Future<void> _retryOn(String contentId, Future<void> Function() action) {
    if (_state.current?.contentId != contentId) {
      return Future<void>.value();
    }
    return action();
  }

  void _reportActionFailure(Failure failure, {Future<void> Function()? retry}) {
    _retry = retry;
    _state = _state.copyWith(
      actionFailure: failure,
      actionFailureId: _state.actionFailureId + 1,
    );
  }

  /// State with [index] on screen and its rating (if any) selected.
  HumorViewState _withCurrent(int index) {
    final items = _state.items;
    final rated = index >= 0 && index < items.length
        ? _ratings[items[index].contentId]
        : null;
    return _state.copyWith(
      currentIndex: index,
      lastRated: rated,
      clearLastRated: rated == null,
    );
  }

  /// Move from the card at [index] to the next one — but only if that card is
  /// still the one on screen, so a late response never jumps the user.
  Future<void> _advanceFrom(
    int index,
    String contentId, {
    required bool fetchAtTail,
  }) async {
    if (_disposed || !_isCurrent(index, contentId)) {
      return;
    }
    final next = index + 1;
    _state = _withCurrent(next);
    notifyListeners();
    if (next < _state.items.length) {
      _markViewed(_state.items[next]);
      await _maybePrefetch();
      return;
    }
    // Past the last loaded card. Calibration pages stop at a stage boundary
    // and carry no cursor, so this is the normal way to reach the next stage,
    // not the end of the feed.
    if (fetchAtTail) {
      await _fetchMore();
    }
  }

  Future<void> _maybePrefetch() async {
    final should = HumorFeedPolicy.shouldPrefetch(
      currentIndex: _state.currentIndex,
      itemCount: _state.items.length,
      hasMore: _state.hasMore,
      isLoadingMore: _state.isLoadingMore || _fetchInFlight != null,
    );
    if (!should) {
      return;
    }
    await _fetchMore();
  }

  /// Single-flight feed request. A caller arriving while one runs waits for
  /// it instead of starting a second.
  Future<void> _fetchMore() async {
    final running = _fetchInFlight;
    if (running != null) {
      await running;
      if (_disposed || !_state.atTail || _state.reachedEnd) {
        return;
      }
      if (_state.loadMoreFailed || _fetchInFlight != null) {
        return;
      }
      // The request that was running did not produce a next card for a user
      // who is now waiting at the end; ask once more on their behalf.
    }
    final future = _runFetchMore();
    _fetchInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_fetchInFlight, future)) {
        _fetchInFlight = null;
      }
    }
  }

  Future<void> _runFetchMore() async {
    final generation = _generation;
    _retry = null;
    _state = _state.copyWith(
      isLoadingMore: true,
      reachedEnd: false,
      loadMoreFailed: false,
    );
    notifyListeners();

    final feed = await _fetchPage(cursor: _state.nextCursor);
    if (_disposed || generation != _generation) {
      return;
    }
    feed.when(
      success: (page) {
        // Calibration pages are recomputed server-side from persisted state,
        // so a page may legitimately repeat items already in the list.
        final existing = _state.items.map((item) => item.contentId).toSet();
        final fresh = page.items
            .where((item) => !existing.contains(item.contentId))
            .toList();
        final waiting = _state.atTail;
        _state = _state.copyWith(
          items: [..._state.items, ...fresh],
          isLoadingMore: false,
          nextCursor: page.nextCursor,
          clearCursor: !page.hasMore,
          profile: _state.profile.copyWith(
            interactionCount: page.interactionCount,
            profileBuilding: page.profileBuilding,
            calibration: page.calibration,
          ),
          calibration: page.calibration,
          catalogExhausted: page.catalogExhausted,
          catalogEmpty: page.catalogEmpty,
          reachedEnd: waiting && fresh.isEmpty,
        );
        if (waiting && fresh.isNotEmpty) {
          // The user was waiting on the empty slot after the last card; it
          // now holds the first new card.
          _state = _withCurrent(_state.currentIndex);
          _markViewed(_state.current);
        }
      },
      err: (failure) {
        _state = _state.copyWith(
          isLoadingMore: false,
          loadMoreFailed: _state.atTail,
        );
        _reportActionFailure(failure, retry: loadMore);
      },
    );
    notifyListeners();
  }

  /// One feed request, following empty pages that still carry a cursor (the
  /// server can end a scan budget without having found anything) a bounded
  /// number of times before treating the feed as empty for now.
  Future<Result<HumorFeedPage>> _fetchPage({required String? cursor}) async {
    var result = await _repository.getFeed(
      languages: _languages,
      limit: HumorFeedPolicy.pageSize,
      cursor: cursor,
    );
    for (var hop = 0; hop < maxEmptyPageHops; hop += 1) {
      final page = result.valueOrNull;
      if (_disposed ||
          page == null ||
          page.items.isNotEmpty ||
          !page.hasMore ||
          page.catalogExhausted) {
        break;
      }
      result = await _repository.getFeed(
        languages: _languages,
        limit: HumorFeedPolicy.pageSize,
        cursor: page.nextCursor,
      );
    }
    return result;
  }

  void _markViewed(HumorContent? item) {
    if (item == null) {
      return;
    }
    _viewStartedAt[item.contentId] = DateTime.now();
    _log(
      AnalyticsEvents.humorContentViewed,
      parameters: {
        'content_id': item.contentId,
        'category': item.category.apiValue,
      },
    );
  }

  int _dwellMs(String contentId) {
    final started = _viewStartedAt[contentId];
    if (started == null) {
      return 0;
    }
    return DateTime.now().difference(started).inMilliseconds.clamp(0, 120000);
  }
}
