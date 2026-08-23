import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_reason_engine.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

abstract final class CompatibilityBreakdownMapper {
  static CompatibilityBreakdown fromCandidate(DiscoveryCandidate candidate) {
    final hasCategories = candidate.categoryRelationshipScore != null;
    return CompatibilityBreakdown(
      overallScore: candidate.compatibilityScore,
      relationshipScore: candidate.categoryRelationshipScore ?? 0,
      interestScore: candidate.categoryInterestScore ?? 0,
      lifestyleScore: candidate.categoryLifestyleScore ?? 0,
      questionScore: candidate.categoryQuestionScore ??
          candidate.relationshipCompatibilityScore,
      musicScore:
          candidate.categoryMusicScore ?? candidate.musicCompatibilityScore,
      communicationScore: candidate.categoryCommunicationScore,
      dataQuality: hasCategories || candidate.compatibilityScore > 0
          ? CompatibilityDataQuality.sufficient
          : CompatibilityDataQuality.partial,
      sharedInterests: candidate.sharedInterests,
      questionAlignedCount: candidate.relationshipAlignedCount,
      questionSharedCount: candidate.relationshipSharedViewCount,
    );
  }

  static List<CompatibilityReason> reasonsFor({
    required UserProfile viewer,
    required DiscoveryCandidate candidate,
    required CompatibilityBreakdown breakdown,
  }) {
    return CompatibilityReasonEngine.build(
      viewer: viewer,
      candidate: UserProfile(
        uid: candidate.uid,
        displayName: candidate.displayName,
        age: candidate.age,
        interests: candidate.interests,
        relationshipGoal: candidate.relationshipGoal,
        city: candidate.city,
      ),
      breakdown: breakdown,
    );
  }
}
