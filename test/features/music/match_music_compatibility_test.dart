import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';

void main() {
  group('MatchMusicCompatibility repository', () {
    test('both connected → available details', () async {
      final source = MockMusicDataSource();
      await source.connectSpotify();
      final repo = MusicRepositoryImpl(dataSource: source);

      final result = await repo.getMatchMusicCompatibility('match-1');
      expect(result, isA<Success<MatchMusicCompatibility>>());
      final value = (result as Success<MatchMusicCompatibility>).value;
      expect(value.available, isTrue);
      expect(value.showDetails, isTrue);
      expect(value.score, 87);
      expect(value.sharedTrackCount, 2);
      expect(value.sharedTracks, isNotEmpty);
    });

    test('disconnected → unavailable', () async {
      final source = MockMusicDataSource();
      final repo = MusicRepositoryImpl(dataSource: source);

      final result = await repo.getMatchMusicCompatibility('match-1');
      final value = (result as Success<MatchMusicCompatibility>).value;
      expect(value.available, isFalse);
      expect(value.showDetails, isFalse);
      expect(value.showTeaser, isFalse);
      expect(value.score, isNull);
    });

    test('unavailable override', () async {
      final source = MockMusicDataSource();
      await source.connectSpotify();
      source.matchMusicOverride = MatchMusicCompatibility.unavailable;
      final repo = MusicRepositoryImpl(dataSource: source);

      final result = await repo.getMatchMusicCompatibility('match-1');
      final value = (result as Success<MatchMusicCompatibility>).value;
      expect(value.available, isFalse);
      expect(value.showDetails, isFalse);
    });

    test('free teaser has no score', () async {
      final source = MockMusicDataSource();
      await source.connectSpotify();
      source.matchMusicOverride = const MatchMusicCompatibility(
        available: true,
        premiumRequired: true,
        teaser: true,
      );
      final repo = MusicRepositoryImpl(dataSource: source);

      final result = await repo.getMatchMusicCompatibility('match-1');
      final value = (result as Success<MatchMusicCompatibility>).value;
      expect(value.available, isTrue);
      expect(value.showTeaser, isTrue);
      expect(value.showDetails, isFalse);
      expect(value.score, isNull);
      expect(value.sharedTracks, isEmpty);
    });
  });

  group('track ID intersection', () {
    MusicTasteSnapshot taste({
      List<String> tracks = const [],
      List<String> artists = const [],
      List<String> genres = const [],
    }) {
      return MusicTasteSnapshot(
        trackIds: tracks,
        artistIds: artists,
        genres: genres,
      );
    }

    test(
      'same track ids match; different ids do not even with same name concept',
      () {
        final sameIds = MusicCompatibilityCalculator.score(
          viewer: taste(
            tracks: ['track-a', 'track-b'],
            artists: ['a1'],
            genres: ['pop'],
          ),
          candidate: taste(
            tracks: ['track-a', 'track-c'],
            artists: ['a1'],
            genres: ['pop'],
          ),
        );
        expect(sameIds.sharedTracks, ['track-a']);
        expect(sameIds.sharedTracks, isNot(contains('track-b')));

        final differentIds = MusicCompatibilityCalculator.score(
          viewer: taste(
            tracks: ['spotify:1'],
            artists: ['a1'],
            genres: ['pop'],
          ),
          candidate: taste(
            tracks: ['spotify:2'],
            artists: ['a1'],
            genres: ['pop'],
          ),
          trackNames: const ['Midnight Tram'],
        );
        expect(differentIds.sharedTracks, isEmpty);
      },
    );
  });
}
