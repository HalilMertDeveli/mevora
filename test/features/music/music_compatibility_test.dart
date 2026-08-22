import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';

void main() {
  MusicTasteSnapshot taste({
    List<String> tracks = const [],
    List<String> artists = const [],
    List<String> genres = const [],
    List<String> recentTracks = const [],
    List<String> recentArtists = const [],
  }) {
    return MusicTasteSnapshot(
      trackIds: tracks,
      artistIds: artists,
      genres: genres,
      recentTrackIds: recentTracks,
      recentArtistIds: recentArtists,
    );
  }

  test('empty or missing Spotify data scores 0', () {
    final result = MusicCompatibilityCalculator.score(
      viewer: const MusicTasteSnapshot(),
      candidate: taste(tracks: ['a'], artists: ['b'], genres: ['pop']),
    );
    expect(result.score, 0);
    expect(result.hasSignal, isFalse);
  });

  test('identical taste scores very high', () {
    final shared = taste(
      tracks: ['t1', 't2', 't3'],
      artists: ['a1', 'a2'],
      genres: ['jazz', 'indie'],
      recentTracks: ['t1'],
      recentArtists: ['a1'],
    );
    final result = MusicCompatibilityCalculator.score(
      viewer: shared,
      candidate: shared,
    );
    expect(result.score, 100);
    expect(result.band, MusicCompatibilityBand.veryHigh);
    expect(result.sharedTracks, containsAll(['t1', 't2', 't3']));
  });

  test('partial overlap lands in mid band', () {
    final result = MusicCompatibilityCalculator.score(
      viewer: taste(
        tracks: ['t1', 't2', 't3', 't4'],
        artists: ['a1', 'a2', 'a3'],
        genres: ['pop', 'rock'],
      ),
      candidate: taste(
        tracks: ['t1', 'x'],
        artists: ['a1', 'y'],
        genres: ['pop', 'folk'],
      ),
    );
    expect(result.score, inInclusiveRange(40, 70));
    expect(result.band, MusicCompatibilityBand.mid);
  });

  test('music ranking bonus never replaces dating score', () {
    expect(MusicCompatibilityCalculator.rankingBonus(0), 0);
    expect(MusicCompatibilityCalculator.rankingBonus(100), 15);
    expect(MusicCompatibilityCalculator.rankingBonus(91), 14);
  });
}
