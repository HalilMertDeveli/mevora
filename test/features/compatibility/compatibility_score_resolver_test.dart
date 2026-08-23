import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_score_resolver.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  const viewer = UserProfile(
    uid: 'a',
    displayName: 'Ada',
    age: 27,
    interests: ['travel', 'music', 'gaming'],
    relationshipGoal: 'longTerm',
    lifestyle: ['smoking:none'],
  );

  const candidateProfile = UserProfile(
    uid: 'b',
    displayName: 'Burak',
    age: 28,
    interests: ['travel', 'music', 'photography'],
    relationshipGoal: 'longTerm',
    lifestyle: ['smoking:none'],
  );

  DiscoveryCandidate candidateFrom(UserProfile profile) {
    return DiscoveryCandidate(
      uid: profile.uid,
      displayName: profile.displayName,
      age: profile.resolvedAge,
      interests: profile.interests,
      relationshipGoal: profile.relationshipGoal,
    );
  }

  test('identical interests and goals produce a high score', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: candidateFrom(candidateProfile),
    );
    expect(resolved.hasCompatibilityScore, isTrue);
    expect(resolved.compatibilityScore, greaterThan(60));
  });

  test('shared interests contribute positively', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: candidateFrom(
        candidateProfile.copyWith(interests: const ['travel', 'music']),
      ),
    );
    expect(resolved.compatibilityScore, greaterThan(50));
    expect(resolved.sharedInterests, contains('travel'));
  });

  test('same relationship goal contributes positively', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: candidateFrom(
        candidateProfile.copyWith(relationshipGoal: 'longTerm'),
      ),
    );
    expect(resolved.compatibilityScore, greaterThan(50));
  });

  test('question overlap increases score when provided', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: DiscoveryCandidate(
        uid: 'b',
        displayName: 'Burak',
        age: 28,
        interests: const ['travel'],
        relationshipGoal: 'longTerm',
        relationshipCompatibilityScore: 90,
        relationshipAlignedCount: 2,
        relationshipSharedViewCount: 3,
      ),
    );
    expect(resolved.compatibilityScore, greaterThan(70));
  });

  test('different profiles produce a lower score than aligned profiles', () {
    final high = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: candidateFrom(candidateProfile),
    );
    final low = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: candidateFrom(
        candidateProfile.copyWith(
          interests: const ['sports'],
          relationshipGoal: 'casual',
        ),
      ),
    );
    expect(high.compatibilityScore, greaterThan(low.compatibilityScore));
  });

  test('partial data does not force score to zero', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: const DiscoveryCandidate(
        uid: 'b',
        displayName: 'Burak',
        age: 28,
        interests: ['travel', 'music'],
        relationshipGoal: 'longTerm',
      ),
    );
    expect(resolved.compatibilityStatus, CompatibilityDisplayStatus.ready);
    expect(resolved.compatibilityScore, greaterThan(0));
  });

  test('empty optional fields are handled gracefully', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: const UserProfile(uid: 'a', displayName: 'Ada', age: 27),
      candidate: const DiscoveryCandidate(
        uid: 'b',
        displayName: 'Burak',
        age: 28,
      ),
    );
    expect(
      resolved.compatibilityStatus,
      isIn([
        CompatibilityDisplayStatus.ready,
        CompatibilityDisplayStatus.unavailable,
      ]),
    );
    if (resolved.compatibilityStatus == CompatibilityDisplayStatus.ready) {
      expect(resolved.compatibilityScore, greaterThan(0));
    }
  });

  test('same pair is deterministic', () {
    final first = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: candidateFrom(candidateProfile),
    );
    final second = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: candidateFrom(candidateProfile),
    );
    expect(first.compatibilityScore, second.compatibilityScore);
  });

  test('server breakdown without top-level score is recovered', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: viewer,
      candidate: const DiscoveryCandidate(
        uid: 'b',
        displayName: 'Burak',
        age: 28,
        interests: ['travel', 'music'],
        relationshipGoal: 'longTerm',
        compatibilityScore: 0,
        categoryInterestScore: 80,
        categoryRelationshipScore: 100,
        categoryLifestyleScore: 70,
      ),
    );
    expect(resolved.hasCompatibilityScore, isTrue);
    expect(resolved.compatibilityScore, greaterThan(0));
  });

  test('missing server and profile data yields unavailable, not fake zero', () {
    final resolved = CompatibilityScoreResolver.resolve(
      viewer: const UserProfile(uid: 'a', displayName: 'Ada'),
      candidate: const DiscoveryCandidate(
        uid: 'b',
        displayName: 'Burak',
        age: 0,
        compatibilityScore: 0,
      ),
    );
    expect(resolved.compatibilityStatus, CompatibilityDisplayStatus.unavailable);
    expect(resolved.hasCompatibilityScore, isFalse);
  });
}
