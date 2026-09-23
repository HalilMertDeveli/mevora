import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';

/// Where the public-music picker is in its lifecycle.
enum PublicMusicPhase { editing, saving, saved }

/// Editing state for "choose what appears on your profile".
///
/// The member picks from their own imported top artists and tracks. Nothing
/// here is authoritative: the ids are sent to the backend, which re-resolves
/// every name, image and link from the member's stored Spotify import.
@immutable
class PublicMusicState {
  const PublicMusicState({
    this.profile = MusicProfile.disconnected,
    this.selectedArtistIds = const {},
    this.selectedTrackIds = const {},
    this.enabled = true,
    this.phase = PublicMusicPhase.editing,
    this.failure,
  });

  final MusicProfile profile;
  final Set<String> selectedArtistIds;
  final Set<String> selectedTrackIds;

  /// Whether the section should be visible on the dating profile at all.
  final bool enabled;

  final PublicMusicPhase phase;
  final Failure? failure;

  List<MusicArtist> get availableArtists => profile.selectableArtists;

  List<MusicTrack> get availableTracks => profile.selectableTracks;

  bool get isSaving => phase == PublicMusicPhase.saving;

  bool get artistLimitReached =>
      selectedArtistIds.length >= maxPublicMusicArtists;

  bool get trackLimitReached =>
      selectedTrackIds.length >= maxPublicMusicTracks;

  bool get hasSelection =>
      selectedArtistIds.isNotEmpty || selectedTrackIds.isNotEmpty;

  /// Spotify returned nothing to choose from. A new account, not a failure.
  bool get hasNothingToOffer =>
      availableArtists.isEmpty && availableTracks.isEmpty;

  bool isArtistSelected(String id) => selectedArtistIds.contains(id);

  bool isTrackSelected(String id) => selectedTrackIds.contains(id);

  /// A fourth pick is refused rather than silently swapping one out.
  bool canSelectArtist(String id) =>
      isArtistSelected(id) || !artistLimitReached;

  bool canSelectTrack(String id) => isTrackSelected(id) || !trackLimitReached;

  PublicMusicState copyWith({
    MusicProfile? profile,
    Set<String>? selectedArtistIds,
    Set<String>? selectedTrackIds,
    bool? enabled,
    PublicMusicPhase? phase,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return PublicMusicState(
      profile: profile ?? this.profile,
      selectedArtistIds: selectedArtistIds ?? this.selectedArtistIds,
      selectedTrackIds: selectedTrackIds ?? this.selectedTrackIds,
      enabled: enabled ?? this.enabled,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class PublicMusicController extends ChangeNotifier {
  PublicMusicController({
    required MusicRepository repository,
    required MusicProfile profile,
  }) : _repository = repository {
    _state = PublicMusicState(
      profile: profile,
      // Re-open on whatever is already published, so editing an existing
      // selection starts from it instead of from a blank sheet.
      selectedArtistIds: profile.publicProfile.artistIds.toSet(),
      selectedTrackIds: profile.publicProfile.trackIds.toSet(),
      enabled: profile.publicProfile.enabled || !profile.publicProfile.hasContent,
    );
  }

  final MusicRepository _repository;
  late PublicMusicState _state;

  PublicMusicState get state => _state;

  void toggleArtist(String id) {
    final next = Set<String>.from(_state.selectedArtistIds);
    if (!next.remove(id)) {
      if (_state.artistLimitReached) {
        return;
      }
      next.add(id);
    }
    _state = _state.copyWith(selectedArtistIds: next, clearFailure: true);
    notifyListeners();
  }

  void toggleTrack(String id) {
    final next = Set<String>.from(_state.selectedTrackIds);
    if (!next.remove(id)) {
      if (_state.trackLimitReached) {
        return;
      }
      next.add(id);
    }
    _state = _state.copyWith(selectedTrackIds: next, clearFailure: true);
    notifyListeners();
  }

  void setEnabled(bool enabled) {
    _state = _state.copyWith(enabled: enabled, clearFailure: true);
    notifyListeners();
  }

  /// Publishes the current selection. Returns true when it was accepted.
  ///
  /// Hiding the section never disconnects Spotify: the import stays, so music
  /// compatibility keeps working while nothing is shown on the profile.
  Future<bool> save() async {
    if (_state.isSaving) {
      return false;
    }
    _state = _state.copyWith(
      phase: PublicMusicPhase.saving,
      clearFailure: true,
    );
    notifyListeners();

    final result = await _repository.updatePublicMusicProfile(
      enabled: _state.enabled,
      artistIds: _state.selectedArtistIds.toList(),
      trackIds: _state.selectedTrackIds.toList(),
    );

    return result.when(
      success: (published) {
        _state = _state.copyWith(
          profile: _state.profile.copyWith(publicProfile: published),
          selectedArtistIds: published.artistIds.toSet(),
          selectedTrackIds: published.trackIds.toSet(),
          enabled: published.enabled,
          phase: PublicMusicPhase.saved,
        );
        notifyListeners();
        return true;
      },
      err: (failure) {
        _state = _state.copyWith(
          phase: PublicMusicPhase.editing,
          failure: failure,
        );
        notifyListeners();
        return false;
      },
    );
  }
}
