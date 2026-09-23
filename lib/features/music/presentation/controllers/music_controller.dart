import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';
import 'package:mevora/features/music/domain/services/music_sync_policy.dart';

enum MusicConnectPhase { idle, connecting, syncing }

class MusicViewState {
  const MusicViewState({
    this.profile = MusicProfile.disconnected,
    this.sameTaste = const [],
    this.weekly = WeeklyMusicStats.empty,
    this.isLoading = false,
    this.loadFailed = false,
    this.phase = MusicConnectPhase.idle,
    this.failure,
  });

  final MusicProfile profile;
  final List<SameTasteMatch> sameTaste;
  final WeeklyMusicStats weekly;
  final bool isLoading;

  /// The profile request itself failed. Distinct from a genuinely
  /// disconnected Spotify account, which is a successful empty result.
  final bool loadFailed;

  final MusicConnectPhase phase;
  final Failure? failure;

  bool get connected => profile.connected;
  bool get canRefresh => MusicSyncPolicy.canSync(
    now: DateTime.now(),
    lastSyncedAt: profile.lastSyncedAt,
  );

  MusicViewState copyWith({
    MusicProfile? profile,
    List<SameTasteMatch>? sameTaste,
    WeeklyMusicStats? weekly,
    bool? isLoading,
    bool? loadFailed,
    MusicConnectPhase? phase,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return MusicViewState(
      profile: profile ?? this.profile,
      sameTaste: sameTaste ?? this.sameTaste,
      weekly: weekly ?? this.weekly,
      isLoading: isLoading ?? this.isLoading,
      loadFailed: loadFailed ?? this.loadFailed,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class MusicController extends ChangeNotifier {
  MusicController({required MusicRepository repository})
    : _repository = repository;

  final MusicRepository _repository;
  MusicViewState _state = const MusicViewState(isLoading: true);

  MusicViewState get state => _state;

  Future<void> load() async {
    _state = _state.copyWith(
      isLoading: true,
      loadFailed: false,
      clearFailure: true,
    );
    notifyListeners();
    final profile = await _repository.getProfile();
    if (profile.isError) {
      // A failed request is not a disconnected account: keep the last
      // known profile and let the page offer a retry instead of the
      // "Connect Spotify" call to action.
      _state = _state.copyWith(
        isLoading: false,
        loadFailed: true,
        failure: profile.failureOrNull,
      );
      notifyListeners();
      return;
    }
    final loaded = profile.valueOrNull ?? MusicProfile.disconnected;
    _state = _state.copyWith(
      profile: loaded,
      isLoading: false,
      loadFailed: false,
    );
    notifyListeners();
    if (loaded.connected) {
      await _loadExtras();
    }
  }

  Future<void> connectSpotify() async {
    if (_state.phase != MusicConnectPhase.idle) {
      return;
    }
    _state = _state.copyWith(
      phase: MusicConnectPhase.connecting,
      clearFailure: true,
    );
    notifyListeners();
    final result = await _repository.connectSpotify();
    result.when(
      success: (profile) {
        _state = _state.copyWith(
          profile: profile,
          phase: MusicConnectPhase.idle,
          loadFailed: false,
        );
      },
      err: (failure) {
        _state = _state.copyWith(
          phase: MusicConnectPhase.idle,
          failure: failure,
        );
      },
    );
    notifyListeners();
    if (_state.connected) {
      await _loadExtras();
    }
  }

  Future<void> syncTaste() async {
    if (!_state.connected || _state.phase != MusicConnectPhase.idle) {
      return;
    }
    if (!_state.canRefresh) {
      return;
    }
    _state = _state.copyWith(
      phase: MusicConnectPhase.syncing,
      clearFailure: true,
    );
    notifyListeners();
    final result = await _repository.syncTaste();
    result.when(
      success: (profile) {
        _state = _state.copyWith(
          profile: profile,
          phase: MusicConnectPhase.idle,
        );
      },
      err: (failure) {
        _state = _state.copyWith(
          phase: MusicConnectPhase.idle,
          failure: failure,
        );
      },
    );
    notifyListeners();
    if (_state.connected) {
      await _loadExtras();
    }
  }

  Future<void> disconnect() async {
    final result = await _repository.disconnectSpotify();
    if (result.isSuccess) {
      _state = const MusicViewState();
    } else {
      _state = _state.copyWith(failure: result.failureOrNull);
    }
    notifyListeners();
  }

  Future<void> _loadExtras() async {
    final same = await _repository.getSameTasteProfiles();
    final weekly = await _repository.getWeeklyStats();
    _state = _state.copyWith(
      sameTaste: same.valueOrNull ?? const [],
      weekly: weekly.valueOrNull ?? WeeklyMusicStats.empty,
    );
    notifyListeners();
  }
}
