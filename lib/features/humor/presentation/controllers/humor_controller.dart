import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';

class _UndoEntry {
  const _UndoEntry({
    required this.index,
    required this.contentId,
    required this.rating,
  });

  final int index;
  final String contentId;
  final HumorRating rating;
}

class HumorViewState {
  const HumorViewState({
    this.items = const [],
    this.currentIndex = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.failure,
    this.profile = UserHumorProfile.empty,
    this.nextCursor,
    this.lastRated,
    this.replayToken = 0,
    this.canUndo = false,
  });

  final List<HumorContent> items;
  final int currentIndex;
  final bool isLoading;
  final bool isLoadingMore;
  final Failure? failure;
  final UserHumorProfile profile;
  final String? nextCursor;
  final HumorRating? lastRated;
  final int replayToken;
  final bool canUndo;

  bool get isEmpty => !isLoading && failure == null && items.isEmpty;
  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

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
    Failure? failure,
    bool clearFailure = false,
    UserHumorProfile? profile,
    String? nextCursor,
    bool clearCursor = false,
    HumorRating? lastRated,
    bool clearLastRated = false,
    int? replayToken,
    bool? canUndo,
  }) {
    return HumorViewState(
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      failure: clearFailure ? null : (failure ?? this.failure),
      profile: profile ?? this.profile,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      lastRated: clearLastRated ? null : (lastRated ?? this.lastRated),
      replayToken: replayToken ?? this.replayToken,
      canUndo: canUndo ?? this.canUndo,
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

  final HumorRepository _repository;
  final AnalyticsProvider? analytics;
  final List<String>? _languages;

  HumorViewState _state = const HumorViewState(isLoading: true);
  _UndoEntry? _undo;
  final Map<String, int> _replayCounts = {};
  final Map<String, DateTime> _viewStartedAt = {};

  HumorViewState get state => _state;

  void _log(String name, {Map<String, Object>? parameters}) {
    final provider = analytics;
    if (provider == null) {
      return;
    }
    unawaited(provider.logEvent(name, parameters: parameters));
  }

  Future<void> load() async {
    _state = _state.copyWith(isLoading: true, clearFailure: true);
    notifyListeners();
    _log(AnalyticsEvents.humorLabOpened);

    final feed = await _repository.getFeed(
      languages: _languages,
      limit: HumorFeedPolicy.pageSize,
    );
    if (feed.isError) {
      _state = _state.copyWith(
        isLoading: false,
        failure: feed.failureOrNull,
        items: const [],
        clearCursor: true,
      );
      notifyListeners();
      return;
    }

    final page = feed.valueOrNull!;
    _undo = null;
    _state = HumorViewState(
      items: page.items,
      currentIndex: 0,
      isLoading: false,
      profile: _state.profile.copyWith(
        interactionCount: page.interactionCount,
        profileBuilding: page.profileBuilding,
      ),
      nextCursor: page.nextCursor,
    );
    notifyListeners();
    _markViewed(page.items.isEmpty ? null : page.items.first);
    await _refreshProfile();
  }

  Future<void> onPageChanged(int index) async {
    if (index < 0 || index >= _state.items.length) {
      return;
    }
    _state = _state.copyWith(currentIndex: index, clearLastRated: true);
    notifyListeners();
    _markViewed(_state.items[index]);
    await _maybePrefetch();
  }

  Future<void> rate(
    HumorRating rating, {
    bool skipped = false,
    bool? swipeUp,
    bool? swipeDown,
  }) async {
    final item = _state.current;
    if (item == null || _state.isLoading) {
      return;
    }
    final contentId = item.contentId;
    final dwell = _dwellMs(contentId);
    final replayCount = _replayCounts[contentId] ?? 0;
    final index = _state.currentIndex;

    final result = await _repository.submitFeedback(
      contentId: contentId,
      rating: rating,
      dwellMs: dwell,
      replayCount: replayCount,
      skipped: skipped,
      swipeUp: swipeUp,
      swipeDown: swipeDown,
    );

    result.when(
      success: (feedback) {
        _undo = _UndoEntry(
          index: index,
          contentId: contentId,
          rating: rating,
        );
        _state = _state.copyWith(
          lastRated: rating,
          canUndo: true,
          profile: _state.profile.copyWith(
            interactionCount: feedback.interactionCount,
            profileBuilding: feedback.profileBuilding,
            confidence: feedback.confidence,
          ),
          clearFailure: true,
        );
        _log(
          skipped
              ? AnalyticsEvents.humorContentSkipped
              : AnalyticsEvents.humorContentRated,
          parameters: {
            'content_id': contentId,
            'rating': rating.apiValue,
          },
        );
      },
      err: (failure) {
        _state = _state.copyWith(failure: failure);
      },
    );
    notifyListeners();

    if (result.isSuccess) {
      await _advanceAfterRate();
    }
  }

  Future<void> skip() => rate(HumorRating.neutral, skipped: true);

  Future<void> rateSwipeUp() =>
      rate(HumorRating.funny, swipeUp: true);

  Future<void> rateSwipeDown() =>
      rate(HumorRating.notFunny, swipeDown: true);

  Future<void> undo() async {
    final entry = _undo;
    if (entry == null) {
      return;
    }
    _undo = null;
    final target = entry.index.clamp(0, _state.items.length - 1);
    _state = _state.copyWith(
      currentIndex: target,
      canUndo: false,
      clearLastRated: true,
    );
    notifyListeners();
    _markViewed(_state.items[target]);
  }

  Future<void> saveCurrent() async {
    final item = _state.current;
    if (item == null) {
      return;
    }
    final result = await _repository.submitFeedback(
      contentId: item.contentId,
      rating: _state.lastRated ?? HumorRating.funny,
      dwellMs: _dwellMs(item.contentId),
      replayCount: _replayCounts[item.contentId] ?? 0,
      saved: true,
    );
    if (result.isSuccess) {
      _log(
        AnalyticsEvents.humorContentSaved,
        parameters: {'content_id': item.contentId},
      );
    } else {
      _state = _state.copyWith(failure: result.failureOrNull);
      notifyListeners();
    }
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
    result.when(
      success: (profile) {
        _state = _state.copyWith(profile: profile);
      },
      err: (_) {},
    );
    notifyListeners();
  }

  Future<void> _advanceAfterRate() async {
    final next = _state.currentIndex + 1;
    if (next < _state.items.length) {
      _state = _state.copyWith(currentIndex: next);
      notifyListeners();
      _markViewed(_state.items[next]);
      await _maybePrefetch();
      return;
    }
    await _maybePrefetch(force: true);
    if (_state.currentIndex + 1 < _state.items.length) {
      final idx = _state.currentIndex + 1;
      _state = _state.copyWith(currentIndex: idx);
      notifyListeners();
      _markViewed(_state.items[idx]);
    }
  }

  Future<void> _maybePrefetch({bool force = false}) async {
    final should = force ||
        HumorFeedPolicy.shouldPrefetch(
          currentIndex: _state.currentIndex,
          itemCount: _state.items.length,
          hasMore: _state.hasMore,
          isLoadingMore: _state.isLoadingMore,
        );
    if (!should) {
      return;
    }
    _state = _state.copyWith(isLoadingMore: true);
    notifyListeners();
    final feed = await _repository.getFeed(
      languages: _languages,
      limit: HumorFeedPolicy.pageSize,
      cursor: _state.nextCursor,
    );
    feed.when(
      success: (page) {
        final merged = [..._state.items, ...page.items];
        _state = _state.copyWith(
          items: merged,
          isLoadingMore: false,
          nextCursor: page.nextCursor,
          clearCursor: !page.hasMore,
          profile: _state.profile.copyWith(
            interactionCount: page.interactionCount,
            profileBuilding: page.profileBuilding,
          ),
        );
      },
      err: (failure) {
        _state = _state.copyWith(isLoadingMore: false, failure: failure);
      },
    );
    notifyListeners();
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
