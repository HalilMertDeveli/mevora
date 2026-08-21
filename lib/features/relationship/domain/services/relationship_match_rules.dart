import 'package:mevora/features/discovery/domain/services/discovery_activity_policy.dart';

/// Relationship Match still respects blocks, passes, gender, and activity.
/// Distance is intentionally not applied here.
abstract final class RelationshipMatchRules {
  static bool isEligible({
    required String selfUid,
    required String candidateUid,
    required Set<String> blocked,
    required Set<String> passed,
    String? viewerGender,
    String? viewerInterestedIn,
    String? candidateGender,
    String? candidateInterestedIn,
    DateTime? lastActiveAt,
    DateTime? now,
    int alignedCount = 0,
  }) {
    if (candidateUid.isEmpty || candidateUid == selfUid) {
      return false;
    }
    if (blocked.contains(candidateUid) || passed.contains(candidateUid)) {
      return false;
    }
    if (alignedCount <= 0) {
      return false;
    }
    if (!DiscoveryActivityPolicy.isEligible(lastActiveAt, now: now)) {
      return false;
    }
    if (!_interestedInAllows(viewerInterestedIn, candidateGender)) {
      return false;
    }
    if (!_interestedInAllows(candidateInterestedIn, viewerGender)) {
      return false;
    }
    return true;
  }

  static bool _interestedInAllows(String? interestedIn, String? gender) {
    final want = interestedIn?.trim().toLowerCase();
    if (want == null || want.isEmpty || want == 'everyone') {
      return true;
    }
    final g = gender?.trim().toLowerCase();
    if (g == null || g.isEmpty) {
      return true;
    }
    if (want == 'men') {
      return g == 'man' || g == 'male' || g == 'men';
    }
    if (want == 'women') {
      return g == 'woman' || g == 'female' || g == 'women';
    }
    return true;
  }
}
