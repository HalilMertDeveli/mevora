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
/// How many top artists and top tracks the Music Profile shows. Mirrors
/// PROFILE_TOP_LIMIT in functions/src/spotifyMusic.ts.
const int profileTopItemLimit = 5;

/// How many followed artists the Music Profile shows. Mirrors
/// FOLLOWED_ARTIST_LIMIT in functions/src/spotifyMusic.ts.
const int followedArtistLimit = 10;

class MusicProfile {
  const MusicProfile({
    required this.connected,
    this.spotifyUserId,
    this.displayName,
    this.topTracks = const [],
    this.topArtists = const [],
    this.recentlyPlayed = const [],
    this.followedArtists = const [],
    this.profileTopArtists = const [],
    this.profileTopTracks = const [],
    this.playlists = const [],
    this.followScopeGranted = false,
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

  /// Artists the member follows on Spotify. A deliberate choice rather
  /// than a play count, so it says something the top lists cannot.
  final List<MusicArtist> followedArtists;

  /// The short lists the Music Profile shows. The fuller [topArtists] and
  /// [topTracks] stay behind them for the selection pool and compatibility.
  final List<MusicArtist> profileTopArtists;
  final List<MusicTrack> profileTopTracks;

  /// The member's own playlists. Names are private to this screen.
  final List<MusicPlaylist> playlists;

  /// False for a connection made before Mevora asked to read follows.
  /// Nothing is broken; the member simply has to reconnect to see them.
  final bool followScopeGranted;

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

  /// True when the member could see followed artists by reconnecting.
  bool get canReconnectForFollowedArtists =>
      connected && !followScopeGranted;

  /// Artists the owner may publish: the ones they listen to most and the
  /// ones they chose to follow. Recently played is excluded — it is
  /// private listening activity, not a chosen favourite.
  List<MusicArtist> get selectableArtists {
    final seen = topArtists.map((artist) => artist.id).toSet();
    return [
      ...topArtists,
      ...followedArtists.where((artist) => !seen.contains(artist.id)),
    ];
  }

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
      followedArtists: followedArtists,
      profileTopArtists: profileTopArtists,
      profileTopTracks: profileTopTracks,
      playlists: playlists,
      followScopeGranted: followScopeGranted,
      genres: genres,
      taste: taste,
      publicProfile: publicProfile ?? this.publicProfile,
      lastSyncedAt: lastSyncedAt,
      connectedAt: connectedAt,
    );
  }
}
