import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';

/// Compact taste snapshot used for compatibility. No tokens, no emails.
class MusicTasteSnapshot {
  const MusicTasteSnapshot({
    this.trackIds = const [],
    this.artistIds = const [],
    this.genres = const [],
    this.recentTrackIds = const [],
    this.recentArtistIds = const [],
    this.playlistTrackIds = const [],
  });

  final List<String> trackIds;
  final List<String> artistIds;
  final List<String> genres;
  final List<String> recentTrackIds;
  final List<String> recentArtistIds;

  /// Spotify playlist track IDs only when playlist scope was granted.
  final List<String> playlistTrackIds;

  bool get isEmpty =>
      trackIds.isEmpty &&
      artistIds.isEmpty &&
      genres.isEmpty &&
      recentTrackIds.isEmpty &&
      recentArtistIds.isEmpty &&
      playlistTrackIds.isEmpty;
}

/// Owner-visible music profile. Full listen history stays on the server.
class MusicProfile {
  const MusicProfile({
    required this.connected,
    this.spotifyUserId,
    this.displayName,
    this.topTracks = const [],
    this.topArtists = const [],
    this.recentlyPlayed = const [],
    this.genres = const [],
    this.taste = const MusicTasteSnapshot(),
    this.publicProfile = PublicMusicProfile.hidden,
    this.lastSyncedAt,
    this.connectedAt,
  });

  final bool connected;
  final String? spotifyUserId;
  final String? displayName;
  final List<MusicTrack> topTracks;
  final List<MusicArtist> topArtists;
  final List<MusicTrack> recentlyPlayed;
  final List<GenreShare> genres;
  final MusicTasteSnapshot taste;

  /// What the owner chose to show on their dating profile. Separate from
  /// [taste], which never leaves their own documents.
  final PublicMusicProfile publicProfile;

  final DateTime? lastSyncedAt;
  final DateTime? connectedAt;

  static const disconnected = MusicProfile(connected: false);

  bool get hasTaste => connected && !taste.isEmpty;

  /// Connected, but Spotify returned nothing worth comparing — a new or
  /// barely used account. Distinct from a failed request.
  bool get hasLimitedData => connected && taste.isEmpty;

  /// Artists the owner may publish. Top artists only: recently played is
  /// private listening activity, not a chosen favourite.
  List<MusicArtist> get selectableArtists => topArtists;

  /// Tracks the owner may publish.
  List<MusicTrack> get selectableTracks => topTracks;

  MusicProfile copyWith({PublicMusicProfile? publicProfile}) {
    return MusicProfile(
      connected: connected,
      spotifyUserId: spotifyUserId,
      displayName: displayName,
      topTracks: topTracks,
      topArtists: topArtists,
      recentlyPlayed: recentlyPlayed,
      genres: genres,
      taste: taste,
      publicProfile: publicProfile ?? this.publicProfile,
      lastSyncedAt: lastSyncedAt,
      connectedAt: connectedAt,
    );
  }
}
