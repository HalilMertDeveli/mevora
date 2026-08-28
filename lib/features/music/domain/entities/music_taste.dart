import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/normalized_music_profile.dart';

/// Compact taste snapshot used for compatibility. No tokens, no emails.
class MusicTasteSnapshot {
  const MusicTasteSnapshot({
    this.trackIds = const [],
    this.artistIds = const [],
    this.genres = const [],
    this.recentTrackIds = const [],
    this.recentArtistIds = const [],
    this.playlistTrackIds = const [],
    this.recentArtists = const [],
  });

  final List<String> trackIds;
  final List<String> artistIds;
  final List<String> genres;
  final List<String> recentTrackIds;
  final List<String> recentArtistIds;
  final List<RecentArtist> recentArtists;

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
    this.provider,
    this.spotifyUserId,
    this.displayName,
    this.topTracks = const [],
    this.topArtists = const [],
    this.recentlyPlayed = const [],
    this.recentArtists = const [],
    this.genres = const [],
    this.taste = const MusicTasteSnapshot(),
    this.lastSyncedAt,
    this.connectedAt,
  });

  final bool connected;
  final String? provider;
  final String? spotifyUserId;
  final String? displayName;
  final List<MusicTrack> topTracks;
  final List<MusicArtist> topArtists;
  final List<MusicTrack> recentlyPlayed;
  final List<RecentArtist> recentArtists;
  final List<GenreShare> genres;
  final MusicTasteSnapshot taste;
  final DateTime? lastSyncedAt;
  final DateTime? connectedAt;

  static const disconnected = MusicProfile(connected: false);

  bool get hasTaste => connected && !taste.isEmpty;

  NormalizedMusicProfileView get normalized => NormalizedMusicProfileView(
    provider: provider,
    recentArtists: recentArtists,
    topGenres: genres,
  );
}
