import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/services/music_match_rules.dart';

void main() {
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

  test('same-taste list is not an automatic match', () {
    expect(
      MusicMatchRules.isEligible(
        selfUid: 'self',
        candidateUid: 'other',
        blocked: const {},
        passed: const {},
      ),
      isTrue,
    );
    expect(
      MusicMatchRules.isEligible(
        selfUid: 'self',
        candidateUid: 'self',
        blocked: const {},
        passed: const {},
      ),
      isFalse,
    );
  });

  test('inactive same-taste profile is not returned as a candidate', () async {
    final now = DateTime.utc(2026, 8, 20);
    final source = MockMusicDataSource(
      clock: () => now,
      lastActiveAtByUid: {
        'music-ada': now.subtract(const Duration(days: 100)),
        'music-leo': now,
      },
    );
    await source.connectSpotify();
    final result = await source.getSameTasteProfiles();
    expect(result.map((item) => item.candidate.uid), ['music-leo']);
  });

  test('missing lastActiveAt still appears in same-taste candidates', () async {
    final source = MockMusicDataSource();
    await source.connectSpotify();
    final result = await source.getSameTasteProfiles();
    expect(result.map((item) => item.candidate.uid), ['music-ada', 'music-leo']);
  });

  test('unconnected music profile does not break same-taste fetch', () async {
    final repository = MusicRepositoryImpl(dataSource: MockMusicDataSource());
    final result = await repository.getSameTasteProfiles();
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, isEmpty);
  });
}
