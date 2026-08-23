import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';

/// Session cache to avoid repeated breakdown work while browsing discover.
class CompatibilitySessionCache {
  final _cache = <String, CompatibilityBreakdown>{};

  String _key(String viewerUid, String candidateUid) => '$viewerUid::$candidateUid';

  CompatibilityBreakdown? get(String viewerUid, String candidateUid) {
    return _cache[_key(viewerUid, candidateUid)];
  }

  void put(String viewerUid, String candidateUid, CompatibilityBreakdown breakdown) {
    _cache[_key(viewerUid, candidateUid)] = breakdown;
  }

  void invalidateViewer(String viewerUid) {
    _cache.removeWhere((key, _) => key.startsWith('$viewerUid::'));
  }

  void clear() => _cache.clear();
}

/// Ranks candidates for discover UI using existing server order as base,
/// then applies a light compatibility-first tiebreak (does not override hard filters).
abstract final class DiscoveryRankingEngine {
  static List<DiscoveryCandidate> applyCompatibilityTiebreak(
    List<DiscoveryCandidate> candidates,
  ) {
    final copy = List<DiscoveryCandidate>.from(candidates);
    copy.sort((a, b) {
      final scoreDiff = b.compatibilityScore.compareTo(a.compatibilityScore);
      if (scoreDiff != 0) {
        return scoreDiff;
      }
      final qA = a.relationshipCompatibilityScore ?? 0;
      final qB = b.relationshipCompatibilityScore ?? 0;
      return qB.compareTo(qA);
    });
    return copy;
  }
}
