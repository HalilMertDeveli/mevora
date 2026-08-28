import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/music/data/datasources/music_data_source.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';
import 'package:mevora/features/music/domain/services/music_match_rules.dart';
import 'package:mevora/features/music/domain/services/music_sync_policy.dart';

/// In-memory Spotify stand-in for tests and when the Web API is not configured.
class MockMusicDataSource implements MusicDataSource {
  MockMusicDataSource({
    this.selfUid = 'self',
    DateTime Function()? clock,
    MusicProfile? connectedProfile,
    List<SameTasteMatch>? sameTaste,
    WeeklyMusicStats? weekly,
    Map<String, DateTime?>? lastActiveAtByUid,
  }) : _clock = clock ?? DateTime.now,
       _connectedSeed = connectedProfile ?? seedProfile,
       _sameTaste = List<SameTasteMatch>.from(sameTaste ?? seedSameTaste),
       _weekly = weekly ?? seedWeekly,
       _lastActiveAtByUid = lastActiveAtByUid ?? const {};

  final String selfUid;
  final DateTime Function() _clock;
  final MusicProfile _connectedSeed;
  final List<SameTasteMatch> _sameTaste;
  final WeeklyMusicStats _weekly;
  final Map<String, DateTime?> _lastActiveAtByUid;
  MusicProfile _profile = MusicProfile.disconnected;
  var connectCalls = 0;
  var syncCalls = 0;
  var failConnect = false;
  var failSync = false;

  static const seedTracks = [
    MusicTrack(
      id: 'mock-track-1',
      name: 'Midnight Tram',
      artist: 'Ada & the Bosphorus',
      genres: ['indie', 'jazz'],
    ),
    MusicTrack(
      id: 'mock-track-2',
      name: 'Golden Horn',
      artist: 'Nesrin Vale',
      genres: ['pop'],
    ),
    MusicTrack(
      id: 'mock-track-3',
      name: 'Galata Nights',
      artist: 'Karaköy Quartet',
      genres: ['jazz'],
    ),
  ];

  static const seedArtists = [
    MusicArtist(
      id: 'mock-artist-1',
      name: 'Ada & the Bosphorus',
      genres: ['indie', 'jazz'],
    ),
    MusicArtist(
      id: 'mock-artist-2',
      name: 'Nesrin Vale',
      genres: ['pop'],
    ),
  ];

  static final seedProfile = MusicProfile(
    connected: true,
    spotifyUserId: 'mock-spotify',
    displayName: 'Mevora Listener',
    topTracks: seedTracks,
    topArtists: seedArtists,
    recentlyPlayed: [seedTracks[0], seedTracks[1]],
    genres: const [
      GenreShare(name: 'indie', percent: 40),
      GenreShare(name: 'jazz', percent: 35),
      GenreShare(name: 'pop', percent: 25),
    ],
    taste: const MusicTasteSnapshot(
      trackIds: ['mock-track-1', 'mock-track-2', 'mock-track-3'],
      artistIds: ['mock-artist-1', 'mock-artist-2'],
      genres: ['indie', 'jazz', 'pop'],
      recentTrackIds: ['mock-track-1', 'mock-track-2'],
      recentArtistIds: ['mock-artist-1', 'mock-artist-2'],
    ),
  );

  static final seedWeekly = WeeklyMusicStats(
    weekId: '2026-W34',
    tracks: [
      WeeklyTrackStat(track: seedTracks[0], playCount: 42),
      WeeklyTrackStat(track: seedTracks[1], playCount: 31),
      WeeklyTrackStat(track: seedTracks[2], playCount: 18),
    ],
  );

  static const seedSameTaste = [
    SameTasteMatch(
      candidate: DiscoveryCandidate(
        uid: 'music-ada',
        displayName: 'Ada',
        age: 27,
        photos: [],
        city: 'Istanbul',
        compatibilityScore: 78,
        musicCompatibilityScore: 91,
        interests: ['music', 'travel'],
        gender: 'woman',
        isDemo: true,
      ),
      musicScore: 91,
      sharedArtists: ['Ada & the Bosphorus'],
      sharedTracks: ['Midnight Tram'],
      sharedGenres: ['jazz'],
      sharedArtistCount: 1,
      sharedTrackCount: 1,
      sharedGenreCount: 1,
    ),
    SameTasteMatch(
      candidate: DiscoveryCandidate(
        uid: 'music-leo',
        displayName: 'Leo',
        age: 29,
        photos: [],
        city: 'Ankara',
        compatibilityScore: 71,
        musicCompatibilityScore: 64,
        interests: ['vinyl', 'coffee'],
        gender: 'man',
        isDemo: true,
      ),
      musicScore: 64,
      sharedArtists: ['Nesrin Vale'],
      sharedArtistCount: 1,
    ),
  ];

  @override
  Future<MusicProfile> getProfile() async => _profile;

  @override
  Future<MusicProfile> connectSpotify() async {
    connectCalls += 1;
    if (failConnect) {
      throw StateError('spotify-not-configured');
    }
    final now = _clock();
    _profile = MusicProfile(
      connected: true,
      spotifyUserId: _connectedSeed.spotifyUserId,
      displayName: _connectedSeed.displayName,
      topTracks: _connectedSeed.topTracks,
      topArtists: _connectedSeed.topArtists,
      recentlyPlayed: _connectedSeed.recentlyPlayed,
      genres: _connectedSeed.genres,
      taste: _connectedSeed.taste,
      lastSyncedAt: now,
      connectedAt: now,
    );
    return _profile;
  }

  @override
  Future<void> disconnectSpotify() async {
    _profile = MusicProfile.disconnected;
  }

  @override
  Future<MusicProfile> syncTaste() async {
    syncCalls += 1;
    if (!_profile.connected) {
      throw StateError('spotify-not-connected');
    }
    if (failSync) {
      throw StateError('spotify-sync-failed');
    }
    final now = _clock();
    if (!MusicSyncPolicy.canSync(
      now: now,
      lastSyncedAt: _profile.lastSyncedAt,
    )) {
      return _profile;
    }
    _profile = MusicProfile(
      connected: true,
      spotifyUserId: _profile.spotifyUserId,
      displayName: _profile.displayName,
      topTracks: _connectedSeed.topTracks,
      topArtists: _connectedSeed.topArtists,
      recentlyPlayed: _connectedSeed.recentlyPlayed,
      genres: _connectedSeed.genres,
      taste: _connectedSeed.taste,
      lastSyncedAt: now,
      connectedAt: _profile.connectedAt,
    );
    return _profile;
  }

  @override
  Future<WeeklyMusicStats> getWeeklyStats() async => _weekly;

  @override
  Future<List<SameTasteMatch>> getSameTasteProfiles() async {
    if (!_profile.connected) {
      return const [];
    }
    return _sameTaste
        .where(
          (match) => MusicMatchRules.isEligible(
            selfUid: selfUid,
            candidateUid: match.candidate.uid,
            blocked: const {},
            passed: const {},
            lastActiveAt: _lastActiveAtByUid[match.candidate.uid],
            now: _clock(),
          ),
        )
        .toList(growable: false);
  }

  /// Mock scenarios for Match UI / premium gating tests.
  MatchMusicCompatibility? matchMusicOverride;

  @override
  Future<MatchMusicCompatibility> getMatchMusicCompatibility(
    String matchId,
  ) async {
    if (matchMusicOverride != null) {
      return matchMusicOverride!;
    }
    if (!_profile.connected || matchId.isEmpty) {
      return MatchMusicCompatibility.unavailable;
    }
    return MatchMusicCompatibility(
      available: true,
      score: 87,
      overallCompatibilityScore: 89,
      sharedTrackCount: 2,
      sharedArtistCount: 2,
      sharedRecentTrackCount: 1,
      sharedTracks: seedTracks.take(2).toList(),
      sharedArtists: seedArtists,
      sharedGenres: const ['indie', 'jazz'],
      viewerRecentArtists: [
        const RecentArtist(id: 'mock-artist-1', name: 'Ada & the Bosphorus'),
        const RecentArtist(id: 'mock-artist-2', name: 'Nesrin Vale'),
      ],
      peerRecentArtists: [
        const RecentArtist(id: 'mock-artist-1', name: 'Ada & the Bosphorus'),
        const RecentArtist(id: 'mock-artist-3', name: 'Karaköy Quartet'),
      ],
    );
  }
}
