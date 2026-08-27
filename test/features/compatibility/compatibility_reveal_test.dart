import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reveal.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_reveal_builder.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  const viewer = UserProfile(
    uid: 'a',
    displayName: 'Ada',
    age: 28,
    interests: ['coffee', 'hiking'],
    relationshipGoal: 'longTerm',
  );
  const candidate = UserProfile(
    uid: 'b',
    displayName: 'Bora',
    age: 30,
    interests: ['coffee', 'jazz'],
    relationshipGoal: 'longTerm',
  );

  CompatibilityBreakdown breakdown({
    int overall = 94,
    int? music,
    int? question,
    int aligned = 2,
    int shared = 3,
    List<String> interests = const ['coffee'],
  }) {
    return CompatibilityBreakdown(
      overallScore: overall,
      relationshipScore: 100,
      interestScore: 70,
      lifestyleScore: 80,
      questionScore: question,
      musicScore: music,
      sharedInterests: interests,
      questionAlignedCount: question == null ? null : aligned,
      questionSharedCount: question == null ? null : shared,
    );
  }

  test('never invents music without musicScore', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown(music: null, question: 67),
      isPremium: true,
    );
    expect(
      reveal.points.any((p) => p.kind == CompatibilityRevealKind.music),
      isFalse,
    );
  });

  test('never invents questions without shared answers', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown(question: null, music: 88),
      isPremium: true,
    );
    expect(
      reveal.points.any((p) => p.kind == CompatibilityRevealKind.questions),
      isFalse,
    );
  });

  test('free users get at most 2 points and no breakdown', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown(music: 88, question: 67),
      isPremium: false,
      questionTopTopics: const ['personality'],
    );
    expect(reveal.available, isTrue);
    expect(reveal.points.length, lessThanOrEqualTo(2));
    expect(reveal.breakdown, isNull);
    expect(reveal.premiumRequired, isTrue);
  });

  test('premium users get up to 3 points and breakdown', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown(music: 88, question: 67),
      isPremium: true,
      questionTopTopics: const ['personality'],
    );
    expect(reveal.available, isTrue);
    expect(reveal.points.length, 3);
    expect(reveal.breakdown, isNotNull);
  });

  test('musicScore 0 does not invent music reason', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown(music: 0, question: 67),
      isPremium: true,
    );
    expect(
      reveal.points.any((p) => p.kind == CompatibilityRevealKind.music),
      isFalse,
    );
  });

  test('free payload never includes breakdown or answer text keys', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown(music: 88, question: 67),
      isPremium: false,
      questionTopTopics: const ['personality'],
    );
    expect(reveal.breakdown, isNull);
    expect(reveal.points.length, lessThanOrEqualTo(2));
    for (final point in reveal.points) {
      expect(point.messageKey.contains('answerText'), isFalse);
      expect(point.messageKey.contains('answerId'), isFalse);
    }
  });

  test('premium never exceeds 3 points', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown(music: 88, question: 67),
      isPremium: true,
      questionTopTopics: const ['personality', 'communication'],
    );
    expect(reveal.points.length, lessThanOrEqualTo(3));
  });

  test('unavailable when no real overlaps', () {
    final reveal = CompatibilityRevealBuilder.build(
      viewer: viewer,
      candidate: const UserProfile(uid: 'c', displayName: 'C', age: 22),
      breakdown: const CompatibilityBreakdown(
        overallScore: 30,
        relationshipScore: 35,
        interestScore: 20,
        lifestyleScore: 40,
      ),
      isPremium: false,
    );
    expect(reveal.available, isFalse);
    expect(reveal.points, isEmpty);
  });
}
