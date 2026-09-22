import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_filters.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/domain/services/discovery_fallback.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';
import 'package:mevora/features/location/domain/services/location_update_policy.dart';
import 'package:mevora/features/compatibility/domain/entities/hidden_compatibility_insight.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_score_resolver.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_session_cache.dart';
import 'package:mevora/features/compatibility/domain/services/mevora_compatibility_engine.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

enum LocationPromptPhase {
  /// Custom Mevora explanation. Native GPS dialog has not been shown.
  explanation,
  gpsDisabled,
  permanentlyDenied,
  error,
  ready,
}

class DiscoveryFeedState {
  const DiscoveryFeedState({
    this.phase = LocationPromptPhase.explanation,
    this.candidates = const [],
    this.radius = DiscoveryRadius.km25,
    this.filters = const DiscoveryFilters(),
    this.isLoading = false,
    this.errorMessage,
    this.showLikeBurst = false,
    this.matchedCandidate,
    this.matchedMatchId,
    this.activeBoost,
    this.hasSeenEveryone = false,
    this.isMockMode = false,
    this.hasDiscoveryError = false,
    this.hiddenCompatibility,
    this.hiddenCompatibilityDismissed = false,
  });

  final LocationPromptPhase phase;
  final List<DiscoveryCandidate> candidates;
  final DiscoveryRadius radius;
  final DiscoveryFilters filters;
  final bool isLoading;
  final String? errorMessage;
  final bool showLikeBurst;
  final DiscoveryCandidate? matchedCandidate;
  final String? matchedMatchId;
  final Boost? activeBoost;
  final bool hasSeenEveryone;
  final bool isMockMode;
  final bool hasDiscoveryError;
  final HiddenCompatibilityInsight? hiddenCompatibility;
  final bool hiddenCompatibilityDismissed;

  DiscoveryCandidate? get current =>
      candidates.isEmpty ? null : candidates.first;

  List<DiscoveryCandidate> get stackCandidates =>
      candidates.length <= 3 ? candidates : candidates.take(3).toList();

  DiscoveryFeedState copyWith({
    LocationPromptPhase? phase,
    List<DiscoveryCandidate>? candidates,
    DiscoveryRadius? radius,
    DiscoveryFilters? filters,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? showLikeBurst,
    DiscoveryCandidate? matchedCandidate,
    bool clearMatch = false,
    String? matchedMatchId,
    Boost? activeBoost,
    bool clearBoost = false,
    bool? hasSeenEveryone,
    bool? isMockMode,
    bool? hasDiscoveryError,
    HiddenCompatibilityInsight? hiddenCompatibility,
    bool clearHiddenCompatibility = false,
    bool? hiddenCompatibilityDismissed,
  }) {
    return DiscoveryFeedState(
      phase: phase ?? this.phase,
      candidates: candidates ?? this.candidates,
      radius: radius ?? this.radius,
      filters: filters ?? this.filters,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      showLikeBurst: showLikeBurst ?? this.showLikeBurst,
      matchedCandidate: clearMatch
          ? null
          : (matchedCandidate ?? this.matchedCandidate),
      matchedMatchId: clearMatch
          ? null
          : (matchedMatchId ?? this.matchedMatchId),
      activeBoost: clearBoost ? null : (activeBoost ?? this.activeBoost),
      hasSeenEveryone: hasSeenEveryone ?? this.hasSeenEveryone,
      isMockMode: isMockMode ?? this.isMockMode,
      hasDiscoveryError: hasDiscoveryError ?? this.hasDiscoveryError,
      hiddenCompatibility: clearHiddenCompatibility
          ? null
          : (hiddenCompatibility ?? this.hiddenCompatibility),
      hiddenCompatibilityDismissed:
          hiddenCompatibilityDismissed ?? this.hiddenCompatibilityDismissed,
    );
  }
}

/// Loads the signed-in user's profile for client-side compatibility fallback.
typedef ViewerProfileLoader = Future<UserProfile?> Function(String uid);

/// Presentation talks to repositories only. No GPS APIs, no other-user coords.
class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required this.uid,
    required LocationRepository locationRepository,
    required DiscoveryRepository discoveryRepository,
    PurchaseRepository? purchaseRepository,
    LocationSyncCoordinator? locationSync,
    ViewerProfileLoader? viewerProfileLoader,
    bool skipExplanationIfAlreadyGranted = true,
    this.swipeThreshold = 120,
  }) : _locationRepository = locationRepository,
       _discoveryRepository = discoveryRepository,
       _purchaseRepository = purchaseRepository,
       _locationSync = locationSync ?? LocationSyncCoordinator(),
       _viewerProfileLoader = viewerProfileLoader,
       _skipExplanationIfAlreadyGranted = skipExplanationIfAlreadyGranted {
    state = state.copyWith(
      isMockMode:
          discoveryRepository is DemoDiscoverySupport &&
          (discoveryRepository as DemoDiscoverySupport).supportsDemoRestart,
    );
  }

  final String uid;
  final LocationRepository _locationRepository;
  final DiscoveryRepository _discoveryRepository;
  final PurchaseRepository? _purchaseRepository;
  final LocationSyncCoordinator _locationSync;
  final ViewerProfileLoader? _viewerProfileLoader;
  final bool _skipExplanationIfAlreadyGranted;

  UserProfile? _viewerProfile;

  /// Minimum drag distance (px) before a swipe action fires.
  final double swipeThreshold;

  PurchaseRepository? get purchaseRepository => _purchaseRepository;
  DiscoveryRepository get discoveryRepository => _discoveryRepository;

  DiscoveryFeedState state = const DiscoveryFeedState();
  bool declinedLocation = false;

  final Set<String> _actedUserIds = <String>{};

  /// Candidates proven to no longer exist server-side.
  ///
  /// Kept for the whole session and applied to every load, so a prefetch that
  /// was already in flight when the account disappeared cannot put the card
  /// back on the deck.
  final Set<String> _evictedUserIds = <String>{};

  bool _isProcessingAction = false;

  /// Candidates the deck must never (re)admit: already swiped, or evicted.
  bool _isExcluded(String candidateUid) =>
      _actedUserIds.contains(candidateUid) ||
      _evictedUserIds.contains(candidateUid);

  static const int _pageLimit = 15;
  static const int _prefetchThreshold = 3;

  String? _nextCursor;
  bool _loadingMore = false;
  bool _expandDistance = false;

  bool get isProcessingAction => _isProcessingAction;

  final _compatibilityCache = CompatibilitySessionCache();

  /// Cached breakdown for Why You Match sheets (invalidated on profile update).
  CompatibilityBreakdown breakdownFor(DiscoveryCandidate candidate) {
    final cached = _compatibilityCache.get(uid, candidate.uid);
    if (cached != null) {
      return cached;
    }
    final viewer = _viewerProfile ?? UserProfile(uid: uid, displayName: 'You');
    final breakdown = CompatibilityScoreResolver.breakdownFor(
      viewer: viewer,
      candidate: candidate,
      filters: state.filters,
    );
    _compatibilityCache.put(uid, candidate.uid, breakdown);
    return breakdown;
  }

  UserProfile? get viewerProfile => _viewerProfile;

  /// Clears cached compatibility breakdowns and reloads discover feed.
  void onProfileUpdated() {
    _compatibilityCache.invalidateViewer(uid);
    _viewerProfile = null;
    unawaited(loadCandidates());
  }

  Future<UserProfile?> _loadViewerProfile() async {
    if (_viewerProfile != null) {
      return _viewerProfile;
    }
    final loader = _viewerProfileLoader;
    if (loader == null) {
      return null;
    }
    _viewerProfile = await loader(uid);
    return _viewerProfile;
  }

  List<DiscoveryCandidate> _resolveCompatibility(
    List<DiscoveryCandidate> candidates,
    UserProfile? viewer,
  ) {
    if (viewer == null) {
      return candidates;
    }
    return candidates
        .map(
          (candidate) => CompatibilityScoreResolver.resolve(
            viewer: viewer,
            candidate: candidate,
            filters: state.filters,
          ),
        )
        .toList();
  }

  Future<void> start() async {
    unawaited(refreshBoost());
    final flags = (await _locationRepository.loadLocationFlags(
      uid,
    )).valueOrNull;
    if (flags?.locationOnboardingCompleted == true) {
      declinedLocation = flags?.locationEnabled != true;
      state = state.copyWith(phase: LocationPromptPhase.ready);
      notifyListeners();
      await loadCandidates();
      return;
    }
    final permission = await _locationRepository.checkPermission();
    final gpsOn = await _locationRepository.isGpsEnabled();
    if (permission == LocationPermissionStatus.granted && gpsOn) {
      if (_skipExplanationIfAlreadyGranted) {
        await _captureAndLoad();
        return;
      }
    }
    if (permission == LocationPermissionStatus.permanentlyDenied) {
      state = state.copyWith(phase: LocationPromptPhase.permanentlyDenied);
      notifyListeners();
      await loadCandidates();
      return;
    }
    if (!gpsOn && permission == LocationPermissionStatus.granted) {
      state = state.copyWith(phase: LocationPromptPhase.gpsDisabled);
      notifyListeners();
      await loadCandidates();
      return;
    }
    state = state.copyWith(phase: LocationPromptPhase.explanation);
    notifyListeners();
  }

  Future<void> useMyLocation() async {
    state = state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    final gpsOn = await _locationRepository.isGpsEnabled();
    if (!gpsOn) {
      state = state.copyWith(
        phase: LocationPromptPhase.gpsDisabled,
        isLoading: false,
      );
      notifyListeners();
      await loadCandidates();
      return;
    }
    final permission = await _locationRepository.requestPermission();
    if (permission == LocationPermissionStatus.permanentlyDenied) {
      state = state.copyWith(
        phase: LocationPromptPhase.permanentlyDenied,
        isLoading: false,
      );
      notifyListeners();
      await loadCandidates();
      return;
    }
    if (permission != LocationPermissionStatus.granted) {
      declinedLocation = true;
      state = state.copyWith(
        phase: LocationPromptPhase.ready,
        isLoading: false,
      );
      notifyListeners();
      await loadCandidates();
      return;
    }
    await _captureAndLoad();
  }

  Future<void> skipLocation() async {
    declinedLocation = true;
    await _locationRepository.saveLocationFlags(
      LocationFlags(
        uid: uid,
        locationEnabled: false,
        locationOnboardingCompleted: true,
      ),
    );
    state = state.copyWith(phase: LocationPromptPhase.ready, clearError: true);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> openSettings() async {
    await _locationRepository.openAppSettings();
  }

  Future<void> openGpsSettings() async {
    await _locationRepository.openGpsSettings();
  }

  Future<void> setRadius(DiscoveryRadius radius) async {
    state = state.copyWith(radius: radius);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> setFilters(DiscoveryFilters filters) async {
    state = state.copyWith(
      filters: filters,
      radius: DiscoveryRadius.closest(filters.maxDistanceKm),
    );
    notifyListeners();
    await loadCandidates();
  }

  Future<void> refresh() async {
    if (!declinedLocation) {
      final permission = await _locationRepository.checkPermission();
      if (permission == LocationPermissionStatus.granted) {
        await _maybePersistLocation();
      }
    }
    await loadCandidates();
  }

  /// Removes candidates that no longer exist server-side.
  ///
  /// The deck, the queued tail and the prefetched batch are one list, so a
  /// single filter covers all three and the visible card advances naturally
  /// when it is the one removed. Routed through here rather than a
  /// `removeWhere` at each call site so the compatibility cache and the
  /// re-admission guard cannot drift out of step with the deck.
  ///
  /// Idempotent, and a no-op for uids that were never on the deck.
  void evictCandidates(Iterable<String> candidateUids) {
    final uids = candidateUids.where((uid) => uid.isNotEmpty).toSet();
    if (uids.isEmpty) {
      return;
    }
    _evictedUserIds.addAll(uids);
    for (final candidateUid in uids) {
      _compatibilityCache.remove(uid, candidateUid);
    }

    final remaining = state.candidates
        .where((candidate) => !uids.contains(candidate.uid))
        .toList(growable: false);
    if (remaining.length == state.candidates.length) {
      return;
    }

    state = state.copyWith(candidates: remaining);
    notifyListeners();

    if (remaining.isEmpty) {
      unawaited(_reloadWhenDeckEmpty());
    }
  }

  /// Re-checks the cards the viewer can actually see or act on.
  ///
  /// Bounded to the visible stack (at most three profile reads) and run when
  /// Discover becomes visible again, so a candidate deleted while the deck sat
  /// in memory cannot linger — without reloading the deck and losing the
  /// viewer's place, and without a read per queued candidate.
  Future<void> revalidateVisibleCandidates() async {
    final probe = _viewerProfileLoader;
    final visible = state.stackCandidates;
    if (probe == null || visible.isEmpty) {
      return;
    }

    final gone = <String>[];
    for (final candidate in visible) {
      try {
        if (await probe(candidate.uid) == null) {
          gone.add(candidate.uid);
        }
      } on Object {
        // A failed probe is not proof of deletion; leave the card alone.
      }
    }
    if (gone.isNotEmpty) {
      _discoverLog('Evicting ${gone.length} deleted candidate(s)');
      evictCandidates(gone);
    }
  }

  void dismissHiddenCompatibility() {
    state = state.copyWith(hiddenCompatibilityDismissed: true);
    notifyListeners();
  }

  void focusHiddenCompatibility() {
    final insight = state.hiddenCompatibility;
    if (insight == null) {
      return;
    }
    final candidates = List<DiscoveryCandidate>.from(state.candidates);
    final index = candidates.indexWhere((c) => c.uid == insight.candidateUid);
    if (index > 0) {
      final candidate = candidates.removeAt(index);
      candidates.insert(0, candidate);
    }
    state = state.copyWith(
      candidates: candidates,
      hiddenCompatibilityDismissed: true,
    );
    notifyListeners();
  }

  Future<void> exploreAgain() async {
    state = state.copyWith(hasSeenEveryone: false);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> restartDemo() async {
    final demo = _asDemo(_discoveryRepository);
    if (demo == null || !demo.supportsDemoRestart) {
      return;
    }
    demo.restartDemo();
    _actedUserIds.clear();
    _nextCursor = null;
    state = state.copyWith(hasSeenEveryone: false, candidates: const []);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> loadCandidates({
    bool refresh = true,
    bool resetFallback = true,
  }) async {
    if (!refresh && (_loadingMore || _nextCursor == null)) {
      return;
    }

    if (refresh) {
      _nextCursor = null;
      if (resetFallback) {
        _expandDistance = false;
      }
      state = state.copyWith(isLoading: true, clearError: true);
      notifyListeners();
    } else {
      _loadingMore = true;
    }

    await _fetchAndApply(refresh: refresh);

    // Controlled fallback: escalate radius / soft distance when deck is empty.
    if (refresh && state.candidates.isEmpty && !state.hasDiscoveryError) {
      await _escalateUntilCandidatesFound();
    }

    _loadingMore = false;
    notifyListeners();
  }

  Future<void> _fetchAndApply({required bool refresh}) async {
    _discoverLog(
      'Fetching candidates radius=${state.radius.kilometers} '
      'expand=$_expandDistance cursor=${refresh ? 'null' : _nextCursor}',
    );
    final result = await _discoveryRepository.getCandidates(
      radius: state.radius,
      cursor: refresh ? null : _nextCursor,
      limit: _pageLimit,
      expandDistance: _expandDistance,
    );

    final viewer = await _loadViewerProfile();

    switch (result) {
      case Success(:final value):
        _nextCursor = value.nextCursor;
        _discoverLog('Server returned ${value.candidates.length} candidates');
        var filtered = _applyFilters(
          value.candidates,
          relaxDistance: _expandDistance,
        ).where((candidate) => !_isExcluded(candidate.uid)).toList();
        if (filtered.isEmpty && value.candidates.isNotEmpty) {
          _discoverLog(
            'Strict client filters emptied deck — relaxing distance/goal',
          );
          filtered = _applyFilters(
            value.candidates,
            relaxDistance: true,
            relaxSecondary: true,
          ).where((candidate) => !_isExcluded(candidate.uid)).toList();
        }
        final ranked =
            DiscoveryRankingEngine.applyCompatibilityTiebreak(filtered);
        final resolved = _resolveCompatibility(ranked, viewer);
        final merged = refresh
            ? resolved
            : _mergeCandidates(state.candidates, resolved);
        final demo = _asDemo(_discoveryRepository);
        final seenEveryone =
            merged.isEmpty &&
            refresh &&
            _nextCursor == null &&
            demo != null &&
            demo.isExhaustedForRadius(state.radius.kilometers);
        final hidden = refresh
            ? MevoraCompatibilityEngine.hiddenInsight(merged)
            : state.hiddenCompatibility;
        _discoverLog('Final candidates: ${merged.length}');
        state = state.copyWith(
          candidates: merged,
          isLoading: false,
          hasSeenEveryone: seenEveryone,
          hasDiscoveryError: false,
          clearError: true,
          hiddenCompatibility: hidden,
          hiddenCompatibilityDismissed: refresh
              ? false
              : state.hiddenCompatibilityDismissed,
          clearHiddenCompatibility: refresh && hidden == null,
          phase: state.phase == LocationPromptPhase.explanation
              ? LocationPromptPhase.ready
              : state.phase,
        );
      case Err(:final failure):
        if (refresh) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: failure.message,
            hasDiscoveryError: true,
          );
        }
    }
  }

  Future<void> _escalateUntilCandidatesFound() async {
    // Step 1: ask server for soft distance tiers at current radius.
    if (!_expandDistance) {
      _discoverLog('Expanding distance soft tiers...');
      _expandDistance = true;
      await _fetchAndApply(refresh: true);
      if (state.candidates.isNotEmpty || state.hasDiscoveryError) {
        return;
      }
    }

    // Step 2: walk the radius ladder (25 → 50 → 100).
    while (state.candidates.isEmpty && !state.hasDiscoveryError) {
      final nextKm = DiscoveryFallback.nextRadiusKm(state.radius.kilometers);
      if (nextKm == null) {
        _discoverLog('All fallback levels exhausted — empty state');
        break;
      }
      _discoverLog('Escalating radius to ${nextKm}km');
      state = state.copyWith(radius: DiscoveryRadius.fromKilometers(nextKm));
      _expandDistance = true;
      await _fetchAndApply(refresh: true);
    }
  }

  void _discoverLog(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[DISCOVER] $message');
  }

  List<DiscoveryCandidate> _mergeCandidates(
    List<DiscoveryCandidate> existing,
    List<DiscoveryCandidate> incoming,
  ) {
    if (incoming.isEmpty) {
      return existing;
    }
    final seen = existing.map((candidate) => candidate.uid).toSet();
    final appended = incoming
        .where((candidate) => !seen.contains(candidate.uid))
        .toList();
    if (appended.isEmpty) {
      return existing;
    }
    return [...existing, ...appended];
  }

  void _maybePrefetchMore() {
    if (_loadingMore || state.isLoading || _nextCursor == null) {
      return;
    }
    if (state.candidates.length > _prefetchThreshold) {
      return;
    }
    unawaited(loadCandidates(refresh: false));
  }

  Future<void> _reloadWhenDeckEmpty() async {
    if (_nextCursor != null) {
      await loadCandidates(refresh: false);
      if (state.candidates.isEmpty && _nextCursor != null) {
        await loadCandidates(refresh: false);
      }
    }
    if (state.candidates.isEmpty) {
      _expandDistance = true;
      await loadCandidates(refresh: true, resetFallback: false);
    }
  }

  List<DiscoveryCandidate> _applyFilters(
    List<DiscoveryCandidate> items, {
    bool relaxDistance = false,
    bool relaxSecondary = false,
  }) {
    final filters = state.filters;
    return items.where((candidate) {
      // Age safety: never show under 18. Upper bound may soft-relax.
      if (candidate.age > 0 && candidate.age < 18) {
        return false;
      }
      if (candidate.age > 0 &&
          (candidate.age < filters.minAge ||
              (!relaxSecondary && candidate.age > filters.maxAge))) {
        return false;
      }
      if (!relaxDistance &&
          candidate.distanceKm != null &&
          candidate.distanceKm! > filters.maxDistanceKm) {
        return false;
      }
      if (!relaxSecondary &&
          filters.gender != null &&
          candidate.gender != null &&
          candidate.gender != filters.gender) {
        return false;
      }
      if (!relaxSecondary &&
          filters.relationshipGoal != null &&
          candidate.relationshipGoal != null &&
          candidate.relationshipGoal != filters.relationshipGoal) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> onLike(String userId) =>
      _performAction(userId, DiscoveryDecision.like);

  Future<void> hideCandidate(String userId) async {
    if (userId == uid) {
      return;
    }
    if (!_actedUserIds.contains(userId)) {
      await _discoveryRepository.recordDecision(
        candidateUid: userId,
        decision: DiscoveryDecision.pass,
      );
      _actedUserIds.add(userId);
    }
    _removeCandidate(userId);
  }

  void _removeCandidate(String userId) {
    final remaining =
        state.candidates.where((candidate) => candidate.uid != userId).toList();
    if (remaining.length == state.candidates.length) {
      return;
    }
    state = state.copyWith(candidates: remaining);
    notifyListeners();
    if (remaining.isEmpty) {
      unawaited(_reloadWhenDeckEmpty());
    } else {
      _maybePrefetchMore();
    }
  }

  Future<void> onPass(String userId) =>
      _performAction(userId, DiscoveryDecision.pass);

  Future<void> onSuperLike(String userId) =>
      _performAction(userId, DiscoveryDecision.superLike);

  Future<void> decide(DiscoveryDecision decision) async {
    final current = state.current;
    if (current == null) {
      return;
    }
    await _performAction(current.uid, decision);
  }

  Future<void> _performAction(String userId, DiscoveryDecision decision) async {
    if (_isProcessingAction) {
      return;
    }
    if (userId == uid) {
      return;
    }
    // A tap already in flight when the candidate was evicted must not turn into
    // a like or pass against an account that no longer exists.
    if (_evictedUserIds.contains(userId)) {
      return;
    }
    if (_actedUserIds.contains(userId)) {
      return;
    }
    final current = state.current;
    if (current == null || current.uid != userId) {
      return;
    }

    _isProcessingAction = true;
    _actedUserIds.add(userId);

    if (decision == DiscoveryDecision.like ||
        decision == DiscoveryDecision.superLike) {
      state = state.copyWith(showLikeBurst: true);
      notifyListeners();
    }

    final result = await _discoveryRepository.recordDecision(
      candidateUid: userId,
      decision: decision,
    );

    final remaining = state.candidates.skip(1).toList();
    final matched = result.valueOrNull?.matched == true ? current : null;
    state = state.copyWith(
      candidates: remaining,
      showLikeBurst: false,
      matchedCandidate: matched,
      matchedMatchId: result.valueOrNull?.matchId,
      clearMatch: matched == null,
    );
    notifyListeners();

    _isProcessingAction = false;

    if (remaining.isEmpty) {
      await _reloadWhenDeckEmpty();
    } else {
      _maybePrefetchMore();
    }
    notifyListeners();
  }

  void clearMatch() {
    state = state.copyWith(clearMatch: true);
    notifyListeners();
  }

  Future<void> _captureAndLoad() async {
    await _maybePersistLocation();
    state = state.copyWith(phase: LocationPromptPhase.ready, isLoading: false);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> _maybePersistLocation() async {
    final result = await _locationRepository.captureCurrentLocation();
    switch (result) {
      case Success(:final value):
        if (_locationSync.shouldPersist(value)) {
          final persisted = await _locationRepository.persistOwnerLocation(
            uid: uid,
            position: value,
          );
          if (persisted.isSuccess) {
            _locationSync.markPersisted(value);
          }
        }
      case Err(:final failure):
        if (failure is LocationFailure) {
          state = state.copyWith(phase: _phaseFor(failure.kind));
        }
    }
  }

  /// Cached Boost for the Boost button. Not called on every swipe.
  Future<void> refreshBoost() async {
    final repo = _purchaseRepository;
    if (repo == null) {
      return;
    }
    final result = await repo.getActiveBoost(uid);
    final boost = result.valueOrNull;
    if (boost == null) {
      if (state.activeBoost != null) {
        state = state.copyWith(clearBoost: true);
        notifyListeners();
      }
      return;
    }
    state = state.copyWith(activeBoost: boost);
    notifyListeners();
  }

  LocationPromptPhase _phaseFor(LocationErrorKind kind) {
    return switch (kind) {
      LocationErrorKind.gpsDisabled => LocationPromptPhase.gpsDisabled,
      LocationErrorKind.permissionPermanentlyDenied =>
        LocationPromptPhase.permanentlyDenied,
      LocationErrorKind.timeout ||
      LocationErrorKind.unavailable ||
      LocationErrorKind.network ||
      LocationErrorKind.invalidCoordinates ||
      LocationErrorKind.error => LocationPromptPhase.error,
      LocationErrorKind.permissionDenied => LocationPromptPhase.ready,
    };
  }

  bool _closed = false;

  @override
  void notifyListeners() {
    if (_closed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

DemoDiscoverySupport? _asDemo(DiscoveryRepository repository) {
  if (repository is DemoDiscoverySupport) {
    return repository as DemoDiscoverySupport;
  }
  return null;
}
