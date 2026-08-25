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

/// Preserves server Discover order with a light client re-rank that mirrors
/// Cloud Functions priority: question alignment → distance → compatibility.
abstract final class DiscoveryRankingEngine {
  static List<DiscoveryCandidate> applyCompatibilityTiebreak(
    List<DiscoveryCandidate> candidates,
  ) {
    final copy = List<DiscoveryCandidate>.from(candidates);
    copy.sort((a, b) {
      final tierDelta = _alignmentTier(b).compareTo(_alignmentTier(a));
      if (tierDelta != 0) {
        return tierDelta;
      }
      final distanceDelta = _distanceKey(a).compareTo(_distanceKey(b));
      if (distanceDelta != 0) {
        return distanceDelta;
      }
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

  static int _alignmentTier(DiscoveryCandidate item) {
    final aligned = item.relationshipAlignedCount ?? 0;
    if (aligned >= 3) {
      return 3;
    }
    if (aligned == 2) {
      return 2;
    }
    if (aligned == 1) {
      return 1;
    }
    return 0;
  }

  static double _distanceKey(DiscoveryCandidate item) {
    return item.distanceKm ?? double.infinity;
  }
}
