import 'package:mevora/core/data/firestore_codec.dart';

/// Hard limits on what a dating profile may show. The backend enforces the
/// same numbers; these exist so the picker can disable a fourth tap instead of
/// letting the member make a selection the server will reject.
const int maxPublicMusicArtists = 3;
const int maxPublicMusicTracks = 3;
const int maxPublicMusicGenres = 3;

/// An artist the member chose to show. Every field is resolved server-side
/// from their own Spotify import — the client never supplies metadata.
class PublicMusicArtist {
  const PublicMusicArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.spotifyUrl,
  });

  final String id;
  final String name;
  final String? imageUrl;

  /// open.spotify.com link, so the card can open the artist in Spotify.
  final String? spotifyUrl;

  static PublicMusicArtist? parse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final id = map['id'] as String?;
    if (id == null || id.isEmpty) {
      return null;
    }
    return PublicMusicArtist(
      id: id,
      name: (map['name'] as String?) ?? '',
      imageUrl: _nonEmpty(map['imageUrl']),
      spotifyUrl: _nonEmpty(map['spotifyUrl']),
    );
  }
}

/// A track the member chose to show.
class PublicMusicTrack {
  const PublicMusicTrack({
    required this.id,
    required this.name,
    this.artist = '',
    this.imageUrl,
    this.spotifyUrl,
  });

  final String id;
  final String name;
  final String artist;
  final String? imageUrl;
  final String? spotifyUrl;

  static PublicMusicTrack? parse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final id = map['id'] as String?;
    if (id == null || id.isEmpty) {
      return null;
    }
    return PublicMusicTrack(
      id: id,
      name: (map['name'] as String?) ?? '',
      artist: (map['artist'] as String?) ?? '',
      imageUrl: _nonEmpty(map['imageUrl']),
      spotifyUrl: _nonEmpty(map['spotifyUrl']),
    );
  }
}

/// The Music Taste section of a dating profile.
///
/// This is deliberately the *whole* of what Spotify contributes to a public
/// profile. The imported taste behind it — recently played, playlist tracks,
/// the compatibility fingerprint — stays in the owner's private documents and
/// is never part of this object.
class PublicMusicProfile {
  const PublicMusicProfile({
    this.enabled = false,
    this.artists = const [],
    this.tracks = const [],
    this.genres = const [],
  });

  final bool enabled;
  final List<PublicMusicArtist> artists;
  final List<PublicMusicTrack> tracks;
  final List<String> genres;

  static const hidden = PublicMusicProfile();

  /// True when there is something worth rendering. A profile with the section
  /// enabled but nothing selected must not draw an empty card.
  bool get hasContent =>
      enabled && (artists.isNotEmpty || tracks.isNotEmpty);

  List<String> get artistIds => artists.map((artist) => artist.id).toList();

  List<String> get trackIds => tracks.map((track) => track.id).toList();

  PublicMusicProfile copyWith({
    bool? enabled,
    List<PublicMusicArtist>? artists,
    List<PublicMusicTrack>? tracks,
    List<String>? genres,
  }) {
    return PublicMusicProfile(
      enabled: enabled ?? this.enabled,
      artists: artists ?? this.artists,
      tracks: tracks ?? this.tracks,
      genres: genres ?? this.genres,
    );
  }

  static PublicMusicProfile parse(Object? raw) {
    if (raw is! Map) {
      return hidden;
    }
    final map = Map<String, dynamic>.from(raw);
    final artists = <PublicMusicArtist>[];
    if (map['artists'] is List) {
      for (final item in map['artists'] as List) {
        final artist = PublicMusicArtist.parse(item);
        if (artist != null) {
          artists.add(artist);
        }
      }
    }
    final tracks = <PublicMusicTrack>[];
    if (map['tracks'] is List) {
      for (final item in map['tracks'] as List) {
        final track = PublicMusicTrack.parse(item);
        if (track != null) {
          tracks.add(track);
        }
      }
    }
    return PublicMusicProfile(
      enabled: map['enabled'] == true,
      artists: artists.take(maxPublicMusicArtists).toList(),
      tracks: tracks.take(maxPublicMusicTracks).toList(),
      genres: firestoreStringList(
        map['genres'],
      ).take(maxPublicMusicGenres).toList(),
    );
  }
}

String? _nonEmpty(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}
