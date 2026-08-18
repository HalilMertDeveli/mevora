import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';

void main() {
  test('match ids are deterministic and ignore order', () {
    expect(MatchEngine.matchId('b', 'a'), MatchEngine.matchId('a', 'b'));
    expect(MatchEngine.matchId('a', 'b'), 'a_b');
  });

  test('rejects self likes and empty ids', () {
    expect(MatchEngine.isValidPair('a', 'a'), isFalse);
    expect(MatchEngine.isValidPair('', 'b'), isFalse);
  });

  test('creates a match only for mutual positive swipes', () {
    final forward = MatchEngine.buildLike(
      fromUserId: 'a',
      toUserId: 'b',
      action: SwipeAction.like,
      createdAt: DateTime(2026),
    );
    final reverse = MatchEngine.buildLike(
      fromUserId: 'b',
      toUserId: 'a',
      action: SwipeAction.superLike,
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
    expect(
      MatchEngine.shouldCreateMatch(
        forward: forward,
        reverse: reverse,
        blocked: true,
        existingActiveMatch: false,
      ),
      isFalse,
    );
  });
}
