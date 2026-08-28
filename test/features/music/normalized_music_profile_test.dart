import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/music/data/datasources/functions_music_data_source.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';

void main() {
  group('NormalizedMusicProfile client parsing', () {
    late FunctionsMusicDataSource source;

    setUp(() {
      source = FunctionsMusicDataSource(
        backend: _ThrowingBackend(),
        connectSpotifyImpl: () async {},
      );
    });

    test('parses provider, recentArtists, and topGenres', () {
      final profile = source.parseProfileForTest({
        'spotifyConnected': true,
        'provider': 'spotify',
        'displayName': 'Test',
        'musicProfileVersion': 3,
        'musicProfile': {
          'trackIds': ['t1'],
          'artistIds': ['a1'],
          'genreNames': ['pop'],
          'recentTrackIds': ['t1'],
          'recentArtistIds': ['a1'],
          'recentArtists': [
            {'id': 'a1', 'name': 'The Weeknd', 'image': 'https://img'},
          ],
          'genres': [
            {'name': 'pop', 'percent': 60},
          ],
        },
        'topTracks': [],
        'topArtists': [],
        'recentlyPlayed': [],
      });

      expect(profile.provider, 'spotify');
      expect(profile.recentArtists, hasLength(1));
      expect(profile.recentArtists.first.name, 'The Weeknd');
      expect(profile.genres.first.name, 'pop');
      expect(profile.normalized.provider, 'spotify');
    });

    test('v2 summary without provider still parses taste', () {
      final profile = source.parseProfileForTest({
        'spotifyConnected': true,
        'musicProfileVersion': 2,
        'musicProfile': {
          'trackIds': ['t1'],
          'artistIds': ['a1'],
          'genreNames': ['jazz'],
          'recentTrackIds': [],
          'recentArtistIds': [],
        },
      });

      expect(profile.connected, isTrue);
      expect(profile.provider, 'spotify');
      expect(profile.taste.trackIds, ['t1']);
      expect(profile.taste.genres, ['jazz']);
      expect(profile.recentArtists, isEmpty);
    });

    test('client payload never exposes token fields on profile model', () {
      final profile = source.parseProfileForTest({
        'spotifyConnected': true,
        'provider': 'spotify',
        'accessToken': 'secret',
        'refreshToken': 'secret',
        'clientSecret': 'secret',
        'musicProfile': {
          'trackIds': ['t1'],
          'artistIds': ['a1'],
          'genreNames': ['pop'],
        },
      });

      expect(profile.connected, isTrue);
      expect(profile.taste.trackIds, ['t1']);
    });

    test('disconnected profile stays disconnected', () {
      final profile = source.parseProfileForTest({'spotifyConnected': false});

      expect(profile.connected, isFalse);
      expect(profile.provider, isNull);
      expect(profile.hasTaste, isFalse);
    });
  });

  test('existing music compatibility score unchanged', () {
    const viewer = MusicTasteSnapshot(
      trackIds: ['t1', 't2'],
      artistIds: ['a1'],
      genres: ['pop'],
      recentTrackIds: ['t1'],
      recentArtistIds: ['a1'],
    );
    const candidate = MusicTasteSnapshot(
      trackIds: ['t1', 't2'],
      artistIds: ['a1'],
      genres: ['pop'],
      recentTrackIds: ['t1'],
      recentArtistIds: ['a1'],
    );
    final result = MusicCompatibilityCalculator.score(
      viewer: viewer,
      candidate: candidate,
    );
    expect(result.score, 100);
  });

  test('users without Spotify still match on mutual likes', () {
    final forward = MatchEngine.buildLike(
      fromUserId: 'a',
      toUserId: 'b',
      action: SwipeAction.like,
      createdAt: DateTime(2026),
    );
    final reverse = MatchEngine.buildLike(
      fromUserId: 'b',
      toUserId: 'a',
      action: SwipeAction.like,
      createdAt: DateTime(2026),
    );
    expect(
      MatchEngine.shouldCreateMatch(
        forward: forward,
        reverse: reverse,
        blocked: false,
        existingActiveMatch: false,
      ),
      isTrue,
    );
  });
}

class _ThrowingBackend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? payload,
  ]) {
    throw UnimplementedError(name);
  }
}
