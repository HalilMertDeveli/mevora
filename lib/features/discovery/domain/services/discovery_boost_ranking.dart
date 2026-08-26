/// Client-side mirror of server boost ranking rules for mocks and tests.
abstract final class DiscoveryBoostRanking {
  static const int boostPriorityBonus = 35;
  static const double distanceExtensionRatio = 0.25;
  static const int distanceScoreMax = 20;

  static double effectiveRadiusKm(int radiusKm, {required bool boosted}) {
    if (!boosted || radiusKm <= 0) {
      return radiusKm.toDouble();
    }
    return (radiusKm * (1 + distanceExtensionRatio)).clamp(0, 100).toDouble();
  }

  static int distanceRankContribution(
    double? distanceKm,
    int radiusKm, {
    required bool boosted,
  }) {
    if (distanceKm == null) {
      return -2;
    }
    if (radiusKm <= 0) {
      return 0;
    }
    final penaltyFactor = boosted ? 0.5 : 1.0;
    final effectiveDistance = distanceKm * penaltyFactor;
    final normalized = (effectiveDistance / radiusKm).clamp(0.0, 1.0);
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
    final boosted = boostedUids.contains(uid);
    var score = compatibilityScore + musicRankingBonus;
    score += distanceRankContribution(
      distanceKm,
      radiusKm,
      boosted: boosted,
    );
    if (boosted) {
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
      out.addAll(_diversify(group, boostedUids, uidOf));
    }
    return out;
  }

  static List<T> _diversify<T>(
    List<T> sorted,
    Set<String> boostedUids,
    String Function(T item) uidOf,
  ) {
    final boosted = sorted.where((item) => boostedUids.contains(uidOf(item)));
    final normal = sorted.where((item) => !boostedUids.contains(uidOf(item)));
    if (boosted.isEmpty || normal.isEmpty) {
      return sorted;
    }
    final out = <T>[];
    final boostedList = boosted.toList();
    final normalList = normal.toList();
    var boostedIndex = 0;
    var normalIndex = 0;
    while (boostedIndex < boostedList.length ||
        normalIndex < normalList.length) {
      if (boostedIndex < boostedList.length) {
        out.add(boostedList[boostedIndex++]);
      }
      if (normalIndex < normalList.length) {
        out.add(normalList[normalIndex++]);
      }
    }
    return out;
  }
}
