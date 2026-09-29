import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/picks/data/picks_analytics.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/domain/repositories/mevora_picks_repository.dart';

enum PicksPhase { initial, loading, loaded, error }

@immutable
class MevoraPicksState {
  const MevoraPicksState({
    this.phase = PicksPhase.initial,
    this.batch = MevoraPicksBatch.empty,
    this.isRefreshing = false,
    this.pendingUids = const {},
    this.departingUids = const {},
    this.errorMessage,
    this.actionErrorMessage,
    this.matchedPick,
    this.matchedMatchId,
  });

  final PicksPhase phase;
  final MevoraPicksBatch batch;
  final bool isRefreshing;

  /// Picks with a like or pass in flight: their buttons are disabled.
  final Set<String> pendingUids;

  /// Picks decided and animating out. Still in [batch] until the animation ends.
  final Set<String> departingUids;
  final String? errorMessage;

  /// A like or pass that failed. Shown once, then cleared.
  final String? actionErrorMessage;
  final MevoraPick? matchedPick;
  final String? matchedMatchId;

  List<MevoraPick> get picks => batch.picks;

  bool get isInitialLoad =>
      phase == PicksPhase.initial || phase == PicksPhase.loading;

  MevoraPicksState copyWith({
    PicksPhase? phase,
    MevoraPicksBatch? batch,
    bool? isRefreshing,
    Set<String>? pendingUids,
    Set<String>? departingUids,
    String? errorMessage,
    bool clearError = false,
    String? actionErrorMessage,
    bool clearActionError = false,
    MevoraPick? matchedPick,
    String? matchedMatchId,
    bool clearMatch = false,
  }) {
    return MevoraPicksState(
      phase: phase ?? this.phase,
      batch: batch ?? this.batch,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      pendingUids: pendingUids ?? this.pendingUids,
      departingUids: departingUids ?? this.departingUids,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorMessage: clearActionError
          ? null
          : (actionErrorMessage ?? this.actionErrorMessage),
      matchedPick: clearMatch ? null : (matchedPick ?? this.matchedPick),
      matchedMatchId: clearMatch
          ? null
          : (matchedMatchId ?? this.matchedMatchId),
    );
  }
}

/// Mevora Picks for one signed-in member.
///
/// Lifecycle rules live on the server. This controller only mirrors them:
/// a like or pass removes the Pick once the server has recorded it; opening
/// a profile changes nothing; a reload shows whatever the server now holds.
class MevoraPicksController extends ChangeNotifier {
  MevoraPicksController({
    required MevoraPicksRepository repository,
    PicksAnalytics? analytics,
    this.removalDuration = AppDurations.medium,
  }) : _repository = repository,
       _analytics = analytics ?? PicksAnalytics(null);

  final MevoraPicksRepository _repository;
  final PicksAnalytics _analytics;

  /// How long a decided card animates out before it leaves the list.
  final Duration removalDuration;

  MevoraPicksState _state = const MevoraPicksState();
  MevoraPicksState get state => _state;

  /// Every uid decided this session. A decision is sent once, however fast
  /// the buttons are tapped, and a decided Pick never reappears from a stale
  /// reload that raced the decision.
  final Set<String> _decided = <String>{};
  Future<void>? _loading;
  bool _closed = false;

  PicksAnalytics get analytics => _analytics;

  int positionOf(MevoraPick pick) {
    final index = _state.picks.indexWhere((p) => p.uid == pick.uid);
    return index < 0 ? pick.rank : index;
  }

  /// Loads the batch. The first call shows a loading state; later calls
  /// refresh quietly and keep the current cards on screen.
  Future<void> load() {
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final firstLoad = _state.phase != PicksPhase.loaded;
    _emit(
      firstLoad
          ? _state.copyWith(phase: PicksPhase.loading, clearError: true)
          : _state.copyWith(isRefreshing: true),
    );
    final result = await _repository.loadPicks();
    switch (result) {
      case Success(:final value):
        final visible = value.picks
            .where((pick) => !_decided.contains(pick.uid))
            .toList();
        final batch = value.copyWith(picks: visible);
        _emit(
          _state.copyWith(
            phase: PicksPhase.loaded,
            batch: batch,
            isRefreshing: false,
            clearError: true,
          ),
        );
        _analytics.delivered(batch.picks);
      case Err(:final failure):
        _emit(
          firstLoad
              ? _state.copyWith(
                  phase: PicksPhase.error,
                  errorMessage: failure.message,
                  isRefreshing: false,
                )
              // A failed background refresh keeps the cards already shown.
              : _state.copyWith(isRefreshing: false),
        );
    }
  }

  void recordImpression(MevoraPick pick) =>
      _analytics.impression(pick, positionOf(pick));

  /// Opening a profile is not a decision. The Pick stays exactly where it is.
  void recordProfileOpened(MevoraPick pick) =>
      _analytics.profileOpened(pick, positionOf(pick));

  Future<void> like(MevoraPick pick) => _decide(pick, DiscoveryDecision.like);

  Future<void> pass(MevoraPick pick) => _decide(pick, DiscoveryDecision.pass);

  /// "Hide" from the safety sheet: an ordinary pass.
  Future<void> hide(String uid) async {
    final pick = _find(uid);
    if (pick != null) {
      await _decide(pick, DiscoveryDecision.pass);
    }
  }

  /// After a block or report the server already excludes this person; drop
  /// them at once rather than waiting for the next load.
  void removeImmediately(String uid) {
    _decided.add(uid);
    _dropFromBatch(uid);
  }

  Future<void> _decide(MevoraPick pick, DiscoveryDecision decision) async {
    final uid = pick.uid;
    if (_decided.contains(uid) || _state.pendingUids.contains(uid)) {
      return;
    }
    final position = positionOf(pick);
    _emit(
      _state.copyWith(
        pendingUids: {..._state.pendingUids, uid},
        clearActionError: true,
      ),
    );
    final result = await _repository.decide(pick: pick, decision: decision);
    final pending = {..._state.pendingUids}..remove(uid);
    switch (result) {
      case Success(:final value):
        _decided.add(uid);
        if (decision == DiscoveryDecision.pass) {
          _analytics.passed(pick, position);
        } else {
          _analytics.liked(pick, position);
        }
        if (value.matched) {
          _analytics.mutualMatch(pick, position);
        }
        _emit(
          _state.copyWith(
            pendingUids: pending,
            departingUids: {..._state.departingUids, uid},
            matchedPick: value.matched ? pick : null,
            matchedMatchId: value.matched ? value.matchId : null,
          ),
        );
        await Future<void>.delayed(removalDuration);
        _dropFromBatch(uid);
      case Err(:final failure):
        // The Pick stays: nothing was recorded, so nothing is removed.
        _emit(
          _state.copyWith(
            pendingUids: pending,
            actionErrorMessage: failure.message,
          ),
        );
    }
  }

  void _dropFromBatch(String uid) {
    final remaining = _state.picks.where((p) => p.uid != uid).toList();
    final departing = {..._state.departingUids}..remove(uid);
    _emit(
      _state.copyWith(
        batch: _state.batch.copyWith(picks: remaining),
        departingUids: departing,
      ),
    );
  }

  MevoraPick? _find(String uid) {
    for (final pick in _state.picks) {
      if (pick.uid == uid) {
        return pick;
      }
    }
    return null;
  }

  void clearMatch() => _emit(_state.copyWith(clearMatch: true));

  void clearActionError() => _emit(_state.copyWith(clearActionError: true));

  void _emit(MevoraPicksState next) {
    if (_closed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
