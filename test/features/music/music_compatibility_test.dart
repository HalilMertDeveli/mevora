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
    List<String> playlistTracks = const [],
  }) {
    return MusicTasteSnapshot(
      trackIds: tracks,
      artistIds: artists,
      genres: genres,
      recentTrackIds: recentTracks,
      recentArtistIds: recentArtists,
      playlistTrackIds: playlistTracks,
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

  test('identical taste scores very high and is deterministic', () {
    final shared = taste(
      tracks: ['t1', 't2', 't3'],
      artists: ['a1', 'a2'],
      genres: ['jazz', 'indie'],
      recentTracks: ['t1'],
      recentArtists: ['a1'],
    );
    final a = MusicCompatibilityCalculator.score(
      viewer: shared,
      candidate: shared,
    );
    final b = MusicCompatibilityCalculator.score(
      viewer: shared,
      candidate: shared,
    );
    expect(a.score, 100);
    expect(a.score, b.score);
    expect(a.band, MusicCompatibilityBand.veryHigh);
    expect(a.sharedTracks, containsAll(['t1', 't2', 't3']));
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

  test('playlist overlap contributes only when both sides have playlist ids', () {
    final withPlaylist = MusicCompatibilityCalculator.score(
      viewer: taste(
        tracks: ['t1'],
        artists: ['a1'],
        genres: ['pop'],
        playlistTracks: ['p1', 'p2', 'p3', 'p4'],
      ),
      candidate: taste(
        tracks: ['t1'],
        artists: ['a1'],
        genres: ['pop'],
        playlistTracks: ['p1', 'p2', 'x', 'y'],
      ),
    );
    expect(withPlaylist.sharedPlaylistTracks.length, 2);
    expect(withPlaylist.breakdown.playlist, greaterThan(0));
    expect(
      withPlaylist.insights.any(
        (item) => item.code == MusicInsightCode.sharedPlaylistTracks,
      ),
      isTrue,
    );
  });

  test('does not invent play counts in insights', () {
    final result = MusicCompatibilityCalculator.score(
      viewer: taste(tracks: ['t1'], artists: ['a1'], genres: ['r&b']),
      candidate: taste(tracks: ['t1'], artists: ['a1'], genres: ['r&b']),
      artistNames: ['The Weeknd'],
      trackNames: ['Blinding Lights'],
    );
    expect(result.sharedTrackNames, ['Blinding Lights']);
    expect(
      result.insights.any(
        (item) =>
            item.code == MusicInsightCode.topSharedArtist &&
            item.params['name'] == 'The Weeknd',
      ),
      isTrue,
    );
    expect(
      result.insights.any(
        (item) => item.params.keys.any((key) => key.contains('play')),
      ),
      isFalse,
    );
  });

  test('music ranking bonus never replaces dating score', () {
    expect(MusicCompatibilityCalculator.rankingBonus(0), 0);
    expect(MusicCompatibilityCalculator.rankingBonus(100), 15);
    expect(MusicCompatibilityCalculator.rankingBonus(91), 14);
  });
}
