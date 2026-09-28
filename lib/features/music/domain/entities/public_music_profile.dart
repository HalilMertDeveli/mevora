import 'package:mevora/core/data/firestore_codec.dart';

/// Hard limits on what a dating profile may show. The backend enforces the
/// same numbers; these exist so the picker can disable a fourth tap instead of
/// letting the member make a selection the server will reject.
/// Ten, not three: three was too little to describe anyone. The selection pool
/// is unchanged, so this is a wider choice from the same imported data. They
/// are ceilings, never targets — publishing one artist is a fine answer.
const int maxPublicMusicArtists = 10;
const int maxPublicMusicTracks = 10;

/// Genres describe the member's general taste, not just their chosen artists.
/// Mirrors MAX_PUBLIC_GENRES in functions/src/spotifyMusicProfile.ts.
const int maxPublicMusicGenres = 5;

/// The general-taste summary names the few artists the member keeps returning
/// to. It stays short whatever the publishing limit is: it reads as a
/// sentence, not a list. Mirrors MAX_SIGNATURE_ARTISTS in
/// functions/src/musicTasteAnalysis.ts.
const int maxSignatureArtists = 3;

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
    this.taste = PublicMusicTaste.none,
  });

  final bool enabled;
  final List<PublicMusicArtist> artists;
  final List<PublicMusicTrack> tracks;
  final List<String> genres;

  /// What this member generally listens to, derived on the server from months
  /// of listening rather than from the last few days.
  final PublicMusicTaste taste;

  static const hidden = PublicMusicProfile();

  /// True when there is something worth rendering. A profile with the section
  /// enabled but nothing selected must not draw an empty card.
  bool get hasContent =>
      enabled && (artists.isNotEmpty || tracks.isNotEmpty);

  /// True when the member has picked something, whether or not it is currently
  /// on show. Visibility asks this, not [hasContent] — a hidden card still has
  /// a selection to turn back on.
  bool get hasSelection => artists.isNotEmpty || tracks.isNotEmpty;

  List<String> get artistIds => artists.map((artist) => artist.id).toList();

  List<String> get trackIds => tracks.map((track) => track.id).toList();

  PublicMusicProfile copyWith({
    bool? enabled,
    List<PublicMusicArtist>? artists,
    List<PublicMusicTrack>? tracks,
    List<String>? genres,
    PublicMusicTaste? taste,
  }) {
    return PublicMusicProfile(
      enabled: enabled ?? this.enabled,
      artists: artists ?? this.artists,
      tracks: tracks ?? this.tracks,
      genres: genres ?? this.genres,
      taste: taste ?? this.taste,
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
      taste: PublicMusicTaste.parse(map['taste']),
    );
  }
}

/// A short, factual description of what someone generally listens to.
///
/// Every field is a count or a name the backend derived from the member's own
/// top artists and tracks over months. There is nothing here about the person,
/// only about the music: no inferred mood, no personality, and nothing from
/// what they happened to play recently.
class PublicMusicTaste {
  const PublicMusicTaste({
    this.dominantGenre,
    this.secondaryGenres = const [],
    this.signatureArtists = const [],
    this.stableArtistCount = 0,
    this.artistBreadth = 0,
  });

  final String? dominantGenre;
  final List<String> secondaryGenres;

  /// Artists that keep recurring across time windows.
  final List<String> signatureArtists;

  /// How many artists appear in both the medium- and long-term windows.
  final int stableArtistCount;

  /// How many distinct artists the summary was drawn from.
  final int artistBreadth;

  static const none = PublicMusicTaste();

  /// True when there is at least one thing worth saying.
  bool get hasContent =>
      (dominantGenre != null && dominantGenre!.isNotEmpty) ||
      signatureArtists.isNotEmpty;

  static PublicMusicTaste parse(Object? raw) {
    if (raw is! Map) {
      return none;
    }
    final map = Map<String, dynamic>.from(raw);
    final dominant = _nonEmpty(map['dominantGenre']);
    return PublicMusicTaste(
      dominantGenre: dominant,
      secondaryGenres: firestoreStringList(map['secondaryGenres'])
          .take(2)
          .toList(),
      signatureArtists: firestoreStringList(map['signatureArtists'])
          .take(maxSignatureArtists)
          .toList(),
      stableArtistCount: firestoreInt(map['stableArtistCount'], 0),
      artistBreadth: firestoreInt(map['artistBreadth'], 0),
    );
  }
}

String? _nonEmpty(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}
