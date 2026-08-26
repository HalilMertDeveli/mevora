import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/music/data/datasources/music_data_source.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';

/// Cloud Functions surface. The UI never stores Spotify tokens.
class FunctionsMusicDataSource implements MusicDataSource {
  FunctionsMusicDataSource({
    required BackendCallable backend,
    required this.connectSpotifyImpl,
  }) : _backend = backend;

  final BackendCallable _backend;
  final Future<void> Function() connectSpotifyImpl;

  @override
  Future<MusicProfile> getProfile() async {
    final data = await _backend.invoke('getMusicAccount');
    return _parseProfile(data);
  }

  @override
  Future<MusicProfile> connectSpotify() async {
    await connectSpotifyImpl();
    return getProfile();
  }

  @override
  Future<void> disconnectSpotify() async {
    await _backend.invoke('disconnectMusicAccount');
  }

  @override
  Future<MusicProfile> syncTaste() async {
    final data = await _backend.invoke('syncSpotifyTaste');
    return _parseProfile(data);
  }

  @override
  Future<WeeklyMusicStats> getWeeklyStats() async {
    final data = await _backend.invoke('getWeeklyMusicStats');
    return WeeklyMusicStats(
      weekId: (data['weekId'] as String?) ?? '',
      tracks: _parseWeekly(data['tracks']),
    );
  }

  @override
  Future<List<SameTasteMatch>> getSameTasteProfiles() async {
    final data = await _backend.invoke('getSameTasteProfiles');
    final raw = data['items'];
    if (raw is! List) {
      return const [];
    }
    final items = <SameTasteMatch>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final candidate = _parseCandidate(map);
      if (candidate == null) {
        continue;
      }
      final sharedArtists = firestoreStringList(map['sharedArtists']);
      final sharedTracks = firestoreStringList(map['sharedTracks']);
      final sharedGenres = firestoreStringList(map['sharedGenres']);
      items.add(
        SameTasteMatch(
          candidate: candidate,
          musicScore: firestoreInt(map['musicScore'], 0),
          sharedArtists: sharedArtists,
          sharedTracks: sharedTracks,
          sharedGenres: sharedGenres,
          sharedArtistCount: firestoreInt(
            map['sharedArtistCount'],
            sharedArtists.length,
          ),
          sharedTrackCount: firestoreInt(
            map['sharedTrackCount'],
            sharedTracks.length,
          ),
          sharedGenreCount: firestoreInt(
            map['sharedGenreCount'],
            sharedGenres.length,
          ),
        ),
      );
    }
    return items;
  }

  MusicProfile _parseProfile(Map<String, dynamic> data) {
    final connected = data['spotifyConnected'] == true || data['connected'] == true;
    return MusicProfile(
      connected: connected,
      displayName: data['displayName'] as String?,
      spotifyUserId: data['spotifyUserId'] as String?,
      topTracks: _parseTracks(data['topTracks']),
      topArtists: _parseArtists(data['topArtists']),
      recentlyPlayed: _parseTracks(data['recentlyPlayed']),
      genres: _parseGenres(data['musicProfile'] ?? data['genres']),
      taste: _parseTaste(data['musicProfile'] is Map ? data['musicProfile'] : data),
      lastSyncedAt: firestoreDate(data['lastSyncedAt']),
      connectedAt: firestoreDate(data['connectedAt']),
    );
  }

  MusicTasteSnapshot _parseTaste(Object? raw) {
    if (raw is! Map) {
      return const MusicTasteSnapshot();
    }
    final map = Map<String, dynamic>.from(raw);
    return MusicTasteSnapshot(
      trackIds: firestoreStringList(map['trackIds'] ?? map['topTrackIds']),
      artistIds: firestoreStringList(map['artistIds'] ?? map['topArtistIds']),
      genres: firestoreStringList(map['genreNames'] ?? map['genres']),
      recentTrackIds: firestoreStringList(map['recentTrackIds']),
      recentArtistIds: firestoreStringList(map['recentArtistIds']),
      playlistTrackIds: firestoreStringList(map['playlistTrackIds']),
    );
  }

  List<GenreShare> _parseGenres(Object? raw) {
    if (raw is List) {
      final out = <GenreShare>[];
      for (final item in raw) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final name = (map['name'] as String?) ?? (map['genre'] as String?) ?? '';
        if (name.isEmpty) {
          continue;
        }
        out.add(
          GenreShare(name: name, percent: firestoreInt(map['percent'], 0)),
        );
      }
      return out;
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final nested = map['genres'];
      if (nested is Map) {
        final shares = <GenreShare>[];
        nested.forEach((key, value) {
          if (key is! String || key.isEmpty) {
            return;
          }
          shares.add(GenreShare(name: key, percent: firestoreInt(value, 0)));
        });
        shares.sort((a, b) => b.percent.compareTo(a.percent));
        return shares;
      }
      if (nested is List) {
        return _parseGenres(nested);
      }
    }
    return const [];
  }

  List<MusicTrack> _parseTracks(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final tracks = <MusicTrack>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final id = map['id'] as String? ?? map['trackId'] as String?;
      if (id == null || id.isEmpty) {
        continue;
      }
      tracks.add(
        MusicTrack(
          id: id,
          name: (map['name'] as String?) ?? '',
          artist: (map['artist'] as String?) ?? '',
          albumImage: map['image'] as String? ?? map['albumImage'] as String?,
          genres: firestoreStringList(map['genres']),
        ),
      );
    }
    return tracks;
  }

  List<MusicArtist> _parseArtists(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final artists = <MusicArtist>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final id = map['id'] as String? ?? map['artistId'] as String?;
      if (id == null || id.isEmpty) {
        continue;
      }
      artists.add(
        MusicArtist(
          id: id,
          name: (map['name'] as String?) ?? '',
          image: map['image'] as String?,
          genres: firestoreStringList(map['genres']),
        ),
      );
    }
    return artists;
  }

  List<WeeklyTrackStat> _parseWeekly(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final stats = <WeeklyTrackStat>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final tracks = _parseTracks([map]);
      if (tracks.isEmpty) {
        continue;
      }
      stats.add(
        WeeklyTrackStat(
          track: tracks.first,
          playCount: firestoreInt(map['playCount'], 0),
        ),
      );
    }
    return stats;
  }

  DiscoveryCandidate? _parseCandidate(Map<String, dynamic> raw) {
    final uid = raw['uid'] as String?;
    if (uid == null || uid.isEmpty) {
      return null;
    }
    final profile = raw['profile'] is Map
        ? Map<String, dynamic>.from(raw['profile'] as Map)
        : raw;
    profile.remove('latitude');
    profile.remove('longitude');
    profile.remove('geohash');
    final photosRaw = profile['photos'];
    final photos = <String>[];
    if (photosRaw is List) {
      for (final item in photosRaw) {
        if (item is String) {
          photos.add(item);
        }
      }
    }
    final musicScore = firestoreInt(raw['musicScore'], 0);
    return DiscoveryCandidate(
      uid: uid,
      displayName: (profile['displayName'] as String?) ?? '',
      age: firestoreInt(profile['age'], 0),
      photos: photos,
      city: profile['city'] as String?,
      bio: profile['bio'] as String?,
      gender: profile['gender'] as String?,
      interests: firestoreStringList(profile['interests']),
      compatibilityScore: firestoreInt(raw['compatibilityScore'], 0),
      musicCompatibilityScore: musicScore == 0 ? null : musicScore,
      compatibilityReasons: firestoreStringList(raw['compatibilityReasons']),
      sharedInterests: firestoreStringList(raw['sharedInterests']),
    );
  }
}
