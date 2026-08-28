import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/music/data/datasources/functions_music_data_source.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';

class _FakeBackend extends BackendCallable {
  Map<String, dynamic>? lastPayload;
  Map<String, dynamic> response = const {'available': false};

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    lastPayload = data;
    return response;
  }
}

void main() {
  group('Phase 2 — Match music compatibility', () {
    test('1 music compatibility available with server score', () {
      const data = {
        'available': true,
        'score': 84,
        'sharedTrackCount': 2,
        'sharedArtistCount': 2,
        'sharedTracks': [
          {'id': 't1', 'name': 'Blinding Lights', 'artist': 'The Weeknd'},
        ],
        'sharedArtists': [
          {'id': 'a1', 'name': 'The Weeknd'},
        ],
        'sharedGenres': ['R&B', 'Pop'],
      };
      final parsed = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      ).parseMatchMusicForTest(data);

      expect(parsed.available, isTrue);
      expect(parsed.showDetails, isTrue);
      expect(parsed.score, 84);
    });

    test('2 common artists by id', () {
      const data = {
        'available': true,
        'score': 80,
        'sharedArtists': [
          {'id': 'weeknd', 'name': 'The Weeknd'},
          {'id': 'rihanna', 'name': 'Rihanna'},
        ],
      };
      final parsed = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      ).parseMatchMusicForTest(data);

      expect(parsed.sharedArtists.map((a) => a.id), ['weeknd', 'rihanna']);
      expect(parsed.sharedArtists.map((a) => a.name), ['The Weeknd', 'Rihanna']);
    });

    test('3 common tracks by id', () {
      const data = {
        'available': true,
        'score': 80,
        'sharedTracks': [
          {'id': 'track-1', 'name': 'Starboy', 'artist': 'The Weeknd'},
          {'id': 'track-2', 'name': 'One Dance', 'artist': 'Drake'},
        ],
      };
      final parsed = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      ).parseMatchMusicForTest(data);

      expect(parsed.sharedTracks.map((t) => t.id), ['track-1', 'track-2']);
      expect(parsed.sharedTracks.first.name, 'Starboy');
    });

    test('4 similar genres only when present', () {
      const withGenres = {
        'available': true,
        'score': 75,
        'sharedGenres': ['R&B', 'Pop'],
      };
      const withoutGenres = {
        'available': true,
        'score': 75,
        'sharedGenres': <String>[],
      };
      final source = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      );

      expect(
        source.parseMatchMusicForTest(withGenres).sharedGenres,
        ['R&B', 'Pop'],
      );
      expect(source.parseMatchMusicForTest(withoutGenres).sharedGenres, isEmpty);
    });

    test('5 recent five artists for viewer and peer', () {
      const data = {
        'available': true,
        'score': 84,
        'viewerRecentArtists': [
          {'id': 'a1', 'name': 'The Weeknd'},
          {'id': 'a2', 'name': 'Drake'},
        ],
        'peerRecentArtists': [
          {'id': 'a1', 'name': 'The Weeknd'},
          {'id': 'a3', 'name': 'Adele'},
        ],
      };
      final parsed = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      ).parseMatchMusicForTest(data);

      expect(parsed.viewerRecentArtists, hasLength(2));
      expect(parsed.peerRecentArtists.first.id, 'a1');
      expect(parsed.peerRecentArtists.last.name, 'Adele');
    });

    test('6 both Spotify connected mock shows details', () async {
      final source = MockMusicDataSource();
      await source.connectSpotify();
      final repo = MusicRepositoryImpl(dataSource: source);

      final result = await repo.getMatchMusicCompatibility('match-1');
      final value = (result as Success<MatchMusicCompatibility>).value;

      expect(value.available, isTrue);
      expect(value.showDetails, isTrue);
      expect(value.score, 87);
      expect(value.overallCompatibilityScore, 89);
    });

    test('7 one user disconnected → unavailable', () async {
      final source = MockMusicDataSource();
      final repo = MusicRepositoryImpl(dataSource: source);

      final result = await repo.getMatchMusicCompatibility('match-1');
      final value = (result as Success<MatchMusicCompatibility>).value;

      expect(value.available, isFalse);
      expect(value.showDetails, isFalse);
    });

    test('8 both disconnected → UI hidden (unavailable)', () async {
      final source = MockMusicDataSource();
      source.matchMusicOverride = MatchMusicCompatibility.unavailable;
      final repo = MusicRepositoryImpl(dataSource: source);

      final result = await repo.getMatchMusicCompatibility('match-1');
      final value = (result as Success<MatchMusicCompatibility>).value;

      expect(value.available, isFalse);
      expect(value.score, isNull);
    });

    test('9 premium user sees details including recent artists', () async {
      final source = MockMusicDataSource();
      await source.connectSpotify();
      final repo = MusicRepositoryImpl(dataSource: source);

      final value =
          (await repo.getMatchMusicCompatibility('match-1')
                  as Success<MatchMusicCompatibility>)
              .value;

      expect(value.showDetails, isTrue);
      expect(value.viewerRecentArtists, isNotEmpty);
      expect(value.peerRecentArtists, isNotEmpty);
    });

    test('10 free user sees teaser only', () async {
      final backend = _FakeBackend()
        ..response = {
          'available': true,
          'premiumRequired': true,
          'teaser': true,
        };
      final source = FunctionsMusicDataSource(
        backend: backend,
        connectSpotifyImpl: () async {},
      );

      final parsed = await source.getMatchMusicCompatibility('match-1');

      expect(parsed.showTeaser, isTrue);
      expect(parsed.showDetails, isFalse);
      expect(parsed.score, isNull);
      expect(parsed.sharedTracks, isEmpty);
    });

    test('11 client sends matchId for server authorization', () async {
      final backend = _FakeBackend()
        ..response = const {'available': false, 'reason': 'no_match'};
      final source = FunctionsMusicDataSource(
        backend: backend,
        connectSpotifyImpl: () async {},
      );

      await source.getMatchMusicCompatibility('match-abc');

      expect(backend.lastPayload?['matchId'], 'match-abc');
    });

    test('12 server score displayed as-is including zero', () {
      final parsed = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      ).parseMatchMusicForTest({
        'available': true,
        'score': 0,
        'sharedTrackCount': 0,
        'sharedArtistCount': 0,
      });

      expect(parsed.available, isTrue);
      expect(parsed.score, 0);
      expect(parsed.showDetails, isTrue);
    });

    test('13 data_unavailable is not confused with zero score', () {
      final unavailable = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      ).parseMatchMusicForTest({
        'available': false,
        'reason': 'data_unavailable',
      });

      final zeroScore = FunctionsMusicDataSource(
        backend: _FakeBackend(),
        connectSpotifyImpl: () async {},
      ).parseMatchMusicForTest({
        'available': true,
        'score': 0,
      });

      expect(unavailable.available, isFalse);
      expect(unavailable.reason, 'data_unavailable');
      expect(unavailable.score, isNull);
      expect(zeroScore.available, isTrue);
      expect(zeroScore.score, 0);
    });

    test('14 track id intersection regression', () {
      final scored = MusicCompatibilityCalculator.score(
        viewer: const MusicTasteSnapshot(
          trackIds: ['spotify:track-a'],
          artistIds: ['artist-a'],
          genres: ['pop'],
        ),
        candidate: const MusicTasteSnapshot(
          trackIds: ['spotify:track-a', 'spotify:track-b'],
          artistIds: ['artist-a', 'artist-b'],
          genres: ['pop', 'r&b'],
        ),
      );

      expect(scored.sharedTracks, ['spotify:track-a']);
      expect(scored.sharedArtists, contains('artist-a'));
      expect(scored.sharedGenres, contains('pop'));
    });
  });
}
