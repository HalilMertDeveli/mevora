import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_reason_engine.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

abstract final class CompatibilityBreakdownMapper {
  /// Maps a candidate only when the server sent a full core category breakdown.
  static CompatibilityBreakdown? fromCandidateIfComplete(
    DiscoveryCandidate candidate,
  ) {
    if (!candidate.hasCompleteCoreCategoryBreakdown) {
      return null;
    }
    return fromCandidate(candidate);
  }

  static CompatibilityBreakdown fromCandidate(DiscoveryCandidate candidate) {
    return CompatibilityBreakdown(
      overallScore: candidate.compatibilityScore,
      relationshipScore: candidate.categoryRelationshipScore!,
      interestScore: candidate.categoryInterestScore!,
      lifestyleScore: candidate.categoryLifestyleScore!,
      questionScore: candidate.categoryQuestionScore ??
          candidate.relationshipCompatibilityScore,
      musicScore:
          candidate.categoryMusicScore ?? candidate.musicCompatibilityScore,
      communicationScore: candidate.categoryCommunicationScore,
      dataQuality: CompatibilityDataQuality.sufficient,
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
