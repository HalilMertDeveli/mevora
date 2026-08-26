import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  const viewer = UserProfile(
    uid: 'a',
    displayName: 'Ada',
    age: 28,
    city: 'Istanbul',
    interests: ['travel', 'music'],
    relationshipGoal: 'longTerm',
    lifestyle: ['early-riser'],
  );

  test('shared interests and city raise the score', () {
    const close = UserProfile(
      uid: 'b',
      displayName: 'Grace',
      age: 27,
      city: 'Istanbul',
      interests: ['travel', 'cooking'],
      relationshipGoal: 'longTerm',
      lifestyle: ['early-riser'],
      lastActiveAt: null,
    );
    const far = UserProfile(
      uid: 'c',
      displayName: 'Lin',
      age: 41,
      city: 'Berlin',
      interests: ['chess'],
      relationshipGoal: 'friendship',
    );

    final engine = CompatibilityEngine.standard();
    final closeScore = engine
        .evaluate(const CompatibilityContext(viewer: viewer, candidate: close))
        .score;
    final farScore = engine
        .evaluate(const CompatibilityContext(viewer: viewer, candidate: far))
        .score;

    expect(closeScore, greaterThan(farScore));
    expect(closeScore, inInclusiveRange(0, 100));
  });

  test('a new strategy can be added without changing the engine', () {
    final engine = CompatibilityEngine([
      const InterestStrategy(),
      const _AlwaysOneStrategy(),
    ]);
    final result = engine.evaluate(
      const CompatibilityContext(viewer: viewer, candidate: viewer),
    );

    expect(result.score, greaterThan(50));
  });
}

class _AlwaysOneStrategy implements CompatibilityStrategy {
  const _AlwaysOneStrategy();

  @override
  String get id => 'ai';

  @override
  double get weight => 0.5;

  @override
  bool applies(CompatibilityContext context) => true;

  @override
  double score(CompatibilityContext context) => 1;

  @override
  String? reason(CompatibilityContext context) => 'Recommended';
}
