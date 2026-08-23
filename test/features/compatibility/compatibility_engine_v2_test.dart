import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/config/compatibility_weights.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_reason_engine.dart';
import 'package:mevora/features/compatibility/domain/services/mevora_compatibility_engine.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  const viewer = UserProfile(
    uid: 'a',
    displayName: 'Ada',
    age: 27,
    interests: const ['travel', 'music', 'coffee'],
    relationshipGoal: 'longTerm',
    lifestyle: const ['smoking:none'],
  );

  const candidate = UserProfile(
    uid: 'b',
    displayName: 'Burak',
    age: 28,
    interests: const ['travel', 'music', 'design'],
    relationshipGoal: 'longTerm',
    lifestyle: const ['smoking:none'],
  );

  test('overall score increases with shared interests and goals', () {
    final high = MevoraCompatibilityEngine.calculate(
      viewer: viewer,
      candidate: candidate,
      relationshipCompatibilityScore: 90,
      relationshipAlignedCount: 3,
      relationshipSharedCount: 3,
      musicCompatibilityScore: 80,
    );
    final low = MevoraCompatibilityEngine.calculate(
      viewer: viewer,
      candidate: candidate.copyWith(
        interests: const ['sports'],
        relationshipGoal: 'casual',
      ),
      relationshipCompatibilityScore: 0,
      relationshipAlignedCount: 0,
      relationshipSharedCount: 3,
    );
    expect(high.overallScore, greaterThan(low.overallScore));
    expect(high.relationshipScore, greaterThan(low.relationshipScore));
  });

  test('missing question data keeps questionScore null', () {
    final breakdown = MevoraCompatibilityEngine.calculate(
      viewer: viewer,
      candidate: candidate,
    );
    expect(breakdown.questionScore, isNull);
    expect(breakdown.dataQuality, isNot(CompatibilityDataQuality.insufficient));
  });

  test('reason engine emits deterministic shared-interest reason', () {
    final breakdown = MevoraCompatibilityEngine.calculate(
      viewer: viewer,
      candidate: candidate,
      relationshipCompatibilityScore: 100,
      relationshipAlignedCount: 3,
      relationshipSharedCount: 3,
    );
    final reasons = CompatibilityReasonEngine.build(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown,
    );
    expect(reasons, isNotEmpty);
    expect(
      reasons.any((r) => r.messageKey == 'compatReasonSharedInterests'),
      isTrue,
    );
  });

  test('hidden compatibility requires real aligned answers', () {
    const insightCandidate = DiscoveryCandidate(
      uid: 'c',
      displayName: 'Can',
      age: 29,
      compatibilityScore: 80,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
      relationshipCompatibilityScore: 85,
      relationshipAlignedCount: 3,
      relationshipSharedViewCount: 4,
    );
    final insight = MevoraCompatibilityEngine.hiddenInsight([insightCandidate]);
    expect(insight, isNotNull);
    expect(insight!.alignedCount, greaterThanOrEqualTo(
      CompatibilityWeights.hiddenCompatibilityMinAligned,
    ));
  });

  test('hidden compatibility ignores low alignment', () {
    const weak = DiscoveryCandidate(
      uid: 'd',
      displayName: 'Deniz',
      age: 30,
      compatibilityScore: 80,
      relationshipCompatibilityScore: 40,
      relationshipAlignedCount: 1,
      relationshipSharedViewCount: 5,
    );
    expect(MevoraCompatibilityEngine.hiddenInsight([weak]), isNull);
  });
}
