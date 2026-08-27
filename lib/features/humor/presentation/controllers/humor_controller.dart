import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

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
    this.isPremium = false,
    this.adPhase = HumorAdPhase.idle,
    this.feedLocked = false,
    this.sessionAdCount = 0,
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
  final bool isPremium;
  final HumorAdPhase adPhase;
  final bool feedLocked;
  final int sessionAdCount;

  bool get isEmpty => !isLoading && failure == null && items.isEmpty;
  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
  bool get adsBlocked =>
      feedLocked ||
      adPhase == HumorAdPhase.loading ||
      adPhase == HumorAdPhase.shown ||
      adPhase == HumorAdPhase.eligible;

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
    bool? isPremium,
    HumorAdPhase? adPhase,
    bool? feedLocked,
    int? sessionAdCount,
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
      isPremium: isPremium ?? this.isPremium,
      adPhase: adPhase ?? this.adPhase,
      feedLocked: feedLocked ?? this.feedLocked,
      sessionAdCount: sessionAdCount ?? this.sessionAdCount,
    );
  }
}

class HumorController extends ChangeNotifier {
  HumorController({
    required HumorRepository repository,
    this.analytics,
    List<String>? languages,
    HumorAdService? adService,
    HumorAdsSettings adsSettings = HumorAdsSettings.defaults,
    SubscriptionRepository? subscriptionRepository,
    bool isPremium = false,
  }) : _repository = repository,
       _languages = languages,
       _adService = adService ?? const NoopHumorAdService(),
       _adPolicy = HumorAdPolicyController(settings: adsSettings),
       _subscriptionRepository = subscriptionRepository {
    _state = HumorViewState(isLoading: true, isPremium: isPremium);
    if (_subscriptionRepository != null) {
      _premiumSub = _subscriptionRepository.watch().listen(_onPremium);
    }
  }

  final HumorRepository _repository;
  final AnalyticsProvider? analytics;
  final List<String>? _languages;
  final HumorAdService _adService;
  final HumorAdPolicyController _adPolicy;
  final SubscriptionRepository? _subscriptionRepository;

  HumorViewState _state = const HumorViewState(isLoading: true);
  _UndoEntry? _undo;
  final Map<String, int> _replayCounts = {};
  final Map<String, DateTime> _viewStartedAt = {};
  final Set<String> _ratingInFlight = {};
  final Set<String> _sessionSeenIds = {};
  int? _lastViewCountedIndex;
  StreamSubscription<PremiumStatus>? _premiumSub;
  var _adPresentationInFlight = false;
  var _advanceAfterAd = false;
  int? _pageTargetAfterAd;

  HumorViewState get state => _state;
  HumorAdsSettings get adsSettings => _adPolicy.settings;
  HumorAdService get adService => _adService;

  void _onPremium(PremiumStatus status) {
    final wasPremium = _state.isPremium;
    final nowPremium = status.isPremium;
    if (wasPremium == nowPremium) {
      return;
    }
    _state = _state.copyWith(isPremium: nowPremium);
    if (nowPremium) {
      _adPolicy.markAdFinished(completed: true);
      _adPresentationInFlight = false;
      _advanceAfterAd = false;
      _pageTargetAfterAd = null;
      _state = _state.copyWith(
        adPhase: HumorAdPhase.idle,
        feedLocked: false,
      );
      _log(AnalyticsEvents.humorPremiumAdFree);
    }
    notifyListeners();
  }

  void updateAdsSettings(HumorAdsSettings settings) {
    _adPolicy.updateSettings(settings);
  }

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
    if (_state.isPremium) {
      _log(AnalyticsEvents.humorPremiumAdFree);
    }

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
    _sessionSeenIds
      ..clear()
      ..addAll(page.items.map((e) => e.contentId));
    _lastViewCountedIndex = null;
    _adPolicy.resetCounters();
    _adPresentationInFlight = false;
    _advanceAfterAd = false;
    _pageTargetAfterAd = null;
    _state = HumorViewState(
      items: page.items,
      currentIndex: 0,
      isLoading: false,
      profile: _state.profile.copyWith(
        interactionCount: page.interactionCount,
        profileBuilding: page.profileBuilding,
      ),
      nextCursor: page.nextCursor,
      isPremium: page.isPremium ?? _state.isPremium,
      adPhase: HumorAdPhase.idle,
      feedLocked: false,
      sessionAdCount: 0,
    );
    notifyListeners();
    _log(
      AnalyticsEvents.humorFeedPageLoaded,
      parameters: {
        'page_size': page.items.length,
        'has_more': page.hasMore ? 1 : 0,
      },
    );
    _markViewed(page.items.isEmpty ? null : page.items.first);
    await _refreshProfile();
  }

  Future<void> onPageChanged(int index) async {
    if (index < 0 || index >= _state.items.length) {
      return;
    }
    if (_state.adsBlocked && index != _state.currentIndex) {
      notifyListeners();
      return;
    }
    final advancing = index > _state.currentIndex;
    if (advancing) {
      final allowed = await _ensureAdGateBeforeAdvance(
        pageTarget: index,
        fromRateAdvance: false,
      );
      if (!allowed) {
        notifyListeners();
        return;
      }
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
    if (_state.adsBlocked) {
      return;
    }
    final item = _state.current;
    if (item == null || _state.isLoading) {
      return;
    }
    // Binary UI only; coerce legacy levels if any caller still sends them.
    final normalized = switch (rating) {
      HumorRating.funny || HumorRating.veryFunny => HumorRating.funny,
      HumorRating.notFunny ||
      HumorRating.notAtAll ||
      HumorRating.neutral => HumorRating.notFunny,
    };
    final contentId = item.contentId;
    if (_ratingInFlight.contains(contentId)) {
      return;
    }
    _ratingInFlight.add(contentId);

    final dwell = _dwellMs(contentId);
    final replayCount = _replayCounts[contentId] ?? 0;
    final index = _state.currentIndex;

    // Optimistic: advance immediately so rating never blocks playback UX.
    final optimisticCount = _state.profile.interactionCount + 1;
    final optimisticFunny =
        _state.profile.funnyCount +
        (normalized == HumorRating.funny ? 1 : 0);
    final optimisticNotFunny =
        _state.profile.notFunnyCount +
        (normalized == HumorRating.notFunny ? 1 : 0);
    _undo = _UndoEntry(
      index: index,
      contentId: contentId,
      rating: normalized,
    );
    _state = _state.copyWith(
      lastRated: normalized,
      canUndo: true,
      profile: _state.profile.copyWith(
        interactionCount: optimisticCount,
        funnyCount: optimisticFunny,
        notFunnyCount: optimisticNotFunny,
        profileBuilding: optimisticCount < 15,
      ),
      clearFailure: true,
    );
    notifyListeners();
    unawaited(_advanceAfterRate());

    _log(
      skipped
          ? AnalyticsEvents.humorContentSkipped
          : normalized == HumorRating.funny
          ? AnalyticsEvents.humorRatingFunny
          : AnalyticsEvents.humorRatingNotFunny,
      parameters: {
        'content_id': contentId,
        'rating': normalized.apiValue,
      },
    );
    if (!skipped) {
      _log(
        AnalyticsEvents.humorContentRated,
        parameters: {
          'content_id': contentId,
          'rating': normalized.apiValue,
        },
      );
    }

    try {
      final result = await _repository.submitFeedback(
        contentId: contentId,
        rating: normalized,
        dwellMs: dwell,
        replayCount: replayCount,
        skipped: skipped,
        swipeUp: swipeUp,
        swipeDown: swipeDown,
      );

      result.when(
        success: (feedback) {
          _state = _state.copyWith(
            profile: _state.profile.copyWith(
              interactionCount: feedback.interactionCount,
              profileBuilding: feedback.profileBuilding,
              confidence: feedback.confidence,
              funnyCount: feedback.funnyCount,
              notFunnyCount: feedback.notFunnyCount,
            ),
            clearFailure: true,
          );
          _log(AnalyticsEvents.humorProfileUpdated, parameters: {
            'interaction_count': feedback.interactionCount,
          });
        },
        err: (failure) {
          // Soft-fail: UX already advanced; keep a non-blocking failure flag.
          _state = _state.copyWith(failure: failure);
        },
      );
      notifyListeners();
    } finally {
      _ratingInFlight.remove(contentId);
    }
  }

  Future<void> skip() => rate(HumorRating.notFunny, skipped: true);

  /// Drop a broken media item and advance without crashing the feed.
  Future<void> skipBrokenMedia(String contentId) async {
    final items = List<HumorContent>.from(_state.items);
    final index = items.indexWhere((e) => e.contentId == contentId);
    if (index < 0) {
      return;
    }
    items.removeAt(index);
    if (items.isEmpty) {
      _state = _state.copyWith(
        items: const [],
        currentIndex: 0,
        clearLastRated: true,
        canUndo: false,
      );
      notifyListeners();
      await _maybePrefetch();
      return;
    }
    final nextIndex = index.clamp(0, items.length - 1);
    _state = _state.copyWith(
      items: items,
      currentIndex: nextIndex,
      clearLastRated: true,
    );
    notifyListeners();
    _markViewed(items[nextIndex]);
    await _maybePrefetch();
  }

  Future<void> rateSwipeUp() => rate(HumorRating.funny, swipeUp: true);

  Future<void> rateSwipeDown() =>
      rate(HumorRating.notFunny, swipeDown: true);

  Future<void> undo() async {
    if (_state.adsBlocked) {
      return;
    }
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
    if (_state.adsBlocked) {
      return;
    }
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
    if (_state.adsBlocked) {
      return;
    }
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

  /// Called by the page when [HumorAdPhase.eligible] is observed.
  Future<void> presentPendingAd({BuildContext? hostContext}) async {
    if (_state.adPhase != HumorAdPhase.eligible || _adPresentationInFlight) {
      return;
    }
    if (_state.isPremium) {
      _state = _state.copyWith(
        adPhase: HumorAdPhase.idle,
        feedLocked: false,
      );
      notifyListeners();
      await _resumeAfterAd();
      return;
    }
    _adPresentationInFlight = true;
    _adPolicy.markAdStarted();
    _state = _state.copyWith(
      adPhase: HumorAdPhase.loading,
      feedLocked: true,
    );
    notifyListeners();
    _log(AnalyticsEvents.humorAdRequested);

    if (!_adService.isAvailable) {
      await _finishAd(HumorAdResult.failedSoft);
      return;
    }

    _log(AnalyticsEvents.humorAdLoaded);
    _state = _state.copyWith(adPhase: HumorAdPhase.shown);
    notifyListeners();
    _log(AnalyticsEvents.humorAdShown);

    final result = await _adService.show(
      HumorAdRequest(
        placementId: 'humor_lab_feed',
        isPremium: _state.isPremium,
      ),
      hostContext: hostContext,
    );
    await _finishAd(result);
  }

  Future<void> _finishAd(HumorAdResult result) async {
    final completed = result.completed && !result.failed;
    // Soft-fail still unlocks feed so users are never stuck forever.
    _adPolicy.markAdFinished(completed: true);
    _adPresentationInFlight = false;
    if (completed) {
      final nextCount = _state.sessionAdCount + 1;
      _state = _state.copyWith(
        adPhase: HumorAdPhase.completed,
        sessionAdCount: nextCount,
      );
      _log(
        AnalyticsEvents.humorAdCompleted,
        parameters: {
          'session_ads': nextCount,
          'interval': _adPolicy.settings.effectiveInterval,
        },
      );
    } else {
      _state = _state.copyWith(adPhase: HumorAdPhase.failed);
      _log(
        AnalyticsEvents.humorAdFailed,
        parameters: {
          'error_code': result.errorCode ?? 'soft_fail',
        },
      );
    }
    _state = _state.copyWith(
      adPhase: HumorAdPhase.idle,
      feedLocked: false,
    );
    notifyListeners();
    await _resumeAfterAd();
  }

  Future<void> _resumeAfterAd() async {
    final pageTarget = _pageTargetAfterAd;
    final fromRate = _advanceAfterAd;
    _pageTargetAfterAd = null;
    _advanceAfterAd = false;
    if (pageTarget != null &&
        pageTarget >= 0 &&
        pageTarget < _state.items.length) {
      _state = _state.copyWith(currentIndex: pageTarget, clearLastRated: true);
      notifyListeners();
      _markViewed(_state.items[pageTarget]);
      await _maybePrefetch();
      return;
    }
    if (fromRate) {
      await _advanceAfterRateUnlocked();
    }
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
    final allowed = await _ensureAdGateBeforeAdvance(fromRateAdvance: true);
    if (!allowed) {
      return;
    }
    await _advanceAfterRateUnlocked();
  }

  Future<void> _advanceAfterRateUnlocked() async {
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

  /// Returns false while waiting for the page to present an ad.
  Future<bool> _ensureAdGateBeforeAdvance({
    int? pageTarget,
    bool fromRateAdvance = false,
  }) async {
    if (_state.isPremium || !_adPolicy.settings.enabled) {
      return true;
    }
    if (!_adPolicy.isEligible(isPremium: _state.isPremium)) {
      return true;
    }
    _pageTargetAfterAd = pageTarget;
    _advanceAfterAd = fromRateAdvance;
    if (_state.adPhase == HumorAdPhase.idle) {
      _state = _state.copyWith(
        adPhase: HumorAdPhase.eligible,
        feedLocked: true,
      );
      _log(
        AnalyticsEvents.humorAdEligible,
        parameters: {
          'interval': _adPolicy.settings.effectiveInterval,
          'is_premium': 0,
        },
      );
      notifyListeners();
    }
    return false;
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
        final merged = <HumorContent>[..._state.items];
        var added = 0;
        for (final item in page.items) {
          if (_sessionSeenIds.add(item.contentId)) {
            merged.add(item);
            added++;
          }
        }
        // Catalog recycled for infinite feed — allow re-queue of known ids.
        if (added == 0 && page.items.isNotEmpty) {
          for (final item in page.items) {
            _sessionSeenIds.add(item.contentId);
            merged.add(item);
          }
        }
        _state = _state.copyWith(
          items: merged,
          isLoadingMore: false,
          nextCursor: page.nextCursor,
          clearCursor: !page.hasMore,
          isPremium: page.isPremium ?? _state.isPremium,
          profile: _state.profile.copyWith(
            interactionCount: page.interactionCount,
            profileBuilding: page.profileBuilding,
          ),
        );
        _log(
          AnalyticsEvents.humorFeedPageLoaded,
          parameters: {
            'page_size': page.items.length,
            'merged_size': merged.length,
            'has_more': page.hasMore ? 1 : 0,
          },
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
    final index = _state.currentIndex;
    if (_lastViewCountedIndex != index) {
      _lastViewCountedIndex = index;
      _adPolicy.onContentViewed();
    }
  }

  int _dwellMs(String contentId) {
    final started = _viewStartedAt[contentId];
    if (started == null) {
      return 0;
    }
    return DateTime.now().difference(started).inMilliseconds.clamp(0, 120000);
  }

  @override
  void dispose() {
    unawaited(_premiumSub?.cancel());
    super.dispose();
  }
}
