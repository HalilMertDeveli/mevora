/// Client-side mirror of the server Boost ranking rules, for mocks and tests.
///
/// Semantics follow `functions/src/boost/ranking.ts`: Boost is a bounded
/// visibility advantage, never a front-of-queue pass. It does not discount
/// distance, it is withheld below the compatibility floor, and boosted results
/// are spaced by a density cap rather than mechanically interleaved.
abstract final class DiscoveryBoostRanking {
  static const int boostPriorityBonus = 35;
  static const double distanceExtensionRatio = 0.25;
  static const int distanceScoreMax = 20;

  /// Below this compatibility, Boost grants nothing — paying must never float
  /// a poor match past a good one.
  static const int minCompatibility = 45;

  /// At most one boosted profile per this many consecutive results.
  static const int densityWindow = 3;
  static const int maxPerWindow = 1;

  static bool boostAdvantageApplies({
    required String uid,
    required int compatibilityScore,
    required Set<String> boostedUids,
  }) {
    return boostedUids.contains(uid) && compatibilityScore >= minCompatibility;
  }

  static double effectiveRadiusKm(int radiusKm, {required bool boosted}) {
    if (!boosted || radiusKm <= 0) {
      return radiusKm.toDouble();
    }
    return (radiusKm * (1 + distanceExtensionRatio)).clamp(0, 100).toDouble();
  }

  static int distanceRankContribution(double? distanceKm, int radiusKm) {
    if (distanceKm == null) {
      return -2;
    }
    if (radiusKm <= 0) {
      return 0;
    }
    final normalized = (distanceKm / radiusKm).clamp(0.0, 1.0);
    return (distanceScoreMax * (1 - normalized)).round();
  }

  static int rankScore({
    required String uid,
    required int compatibilityScore,
    required int musicRankingBonus,
    required double? distanceKm,
    required int radiusKm,
    required Set<String> boostedUids,
  }) {
    final advantaged = boostAdvantageApplies(
      uid: uid,
      compatibilityScore: compatibilityScore,
      boostedUids: boostedUids,
    );
    var score = compatibilityScore + musicRankingBonus;
    score += distanceRankContribution(distanceKm, radiusKm);
    if (advantaged) {
      score += boostPriorityBonus;
    }
    return score;
  }

  static List<T> sortCandidates<T>({
    required List<T> items,
    required Set<String> boostedUids,
    required int radiusKm,
    required String Function(T item) uidOf,
    required int Function(T item) compatibilityOf,
    required int Function(T item) musicBonusOf,
    required double? Function(T item) distanceOf,
    int Function(T item)? relationshipAlignedOf,
    int Function(T a, T b)? tieBreak,
  }) {
    int alignmentTier(T item) {
      final aligned = relationshipAlignedOf?.call(item) ?? 0;
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

    double distanceKey(T item) {
      final value = distanceOf(item);
      if (value == null) {
        return double.infinity;
      }
      return value;
    }

    final sorted = [...items]..sort((a, b) {
      final tierDelta = alignmentTier(b).compareTo(alignmentTier(a));
      if (tierDelta != 0) {
        return tierDelta;
      }
      final distanceDelta = distanceKey(a).compareTo(distanceKey(b));
      if (distanceDelta != 0) {
        return distanceDelta;
      }
      final aScore = rankScore(
        uid: uidOf(a),
        compatibilityScore: compatibilityOf(a),
        musicRankingBonus: musicBonusOf(a),
        distanceKm: distanceOf(a),
        radiusKm: radiusKm,
        boostedUids: boostedUids,
      );
      final bScore = rankScore(
        uid: uidOf(b),
        compatibilityScore: compatibilityOf(b),
        musicRankingBonus: musicBonusOf(b),
        distanceKm: distanceOf(b),
        radiusKm: radiusKm,
        boostedUids: boostedUids,
      );
      if (bScore != aScore) {
        return bScore.compareTo(aScore);
      }
      return tieBreak?.call(a, b) ?? 0;
    });

    final out = <T>[];
    for (final tier in const [3, 2, 1, 0]) {
      final group = sorted.where((item) => alignmentTier(item) == tier).toList();
      out.addAll(_capDensity(group, boostedUids, uidOf, compatibilityOf));
    }
    return out;
  }

  /// Spaces boosted profiles out without reordering on their behalf: a boosted
  /// item is only ever deferred, never promoted. Mirrors capBoostedDensity.
  static List<T> _capDensity<T>(
    List<T> sorted,
    Set<String> boostedUids,
    String Function(T item) uidOf,
    int Function(T item) compatibilityOf,
  ) {
    bool advantaged(T item) => boostAdvantageApplies(
      uid: uidOf(item),
      compatibilityScore: compatibilityOf(item),
      boostedUids: boostedUids,
    );

    final out = <T>[];
    final deferred = <T>[];

    bool windowIsFull() {
      final start = (out.length - densityWindow + 1).clamp(0, out.length);
      var count = 0;
      for (var i = start; i < out.length; i++) {
        if (advantaged(out[i])) {
          count++;
        }
      }
      return count >= maxPerWindow;
    }

    for (final item in sorted) {
      if (advantaged(item) && windowIsFull()) {
        deferred.add(item);
        continue;
      }
      out.add(item);
      while (deferred.isNotEmpty && !windowIsFull()) {
        out.add(deferred.removeAt(0));
      }
    }
    out.addAll(deferred);
    return out;
  }
}
