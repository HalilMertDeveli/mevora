import 'package:mevora/features/discovery/domain/services/discovery_activity_policy.dart';
import 'package:mevora/features/discovery/domain/services/discovery_boost_ranking.dart';
import 'package:mevora/features/discovery/domain/services/discovery_fallback.dart';

/// Backend-style exclusion + soft distance tiers. Used by the in-memory
/// discovery stand-in and unit tests so the client never scans every user.
abstract final class DiscoveryCandidateFilter {
  static List<T> apply<T extends Object>({
    required List<T> seeds,
    required String selfUid,
    required Set<String> blocked,
    required Set<String> liked,
    required Set<String> passed,
    required int radiusKm,
    Set<String>? boostedUids,
    String Function(T seed)? uidOf,
    double? Function(T seed)? distanceKmOf,
    DateTime? Function(T seed)? lastActiveAtOf,
    DateTime Function()? clock,
    bool expandDistance = false,
    int? limit,
  }) {
    String idOf(T seed) {
      if (uidOf != null) {
        return uidOf(seed);
      }
      final dynamic value = seed;
      return value.uid as String;
    }

    double? kmOf(T seed) {
      if (distanceKmOf != null) {
        return distanceKmOf(seed);
      }
      try {
        final dynamic value = seed;
        return value.distanceKm as double?;
      } on Object {
        return null;
      }
    }

    final buckets = <DiscoveryDistanceTier, List<T>>{
      DiscoveryDistanceTier.nearby: <T>[],
      DiscoveryDistanceTier.extended: <T>[],
      DiscoveryDistanceTier.far: <T>[],
      DiscoveryDistanceTier.noLocation: <T>[],
    };

    for (final seed in seeds) {
      final uid = idOf(seed);
      if (uid == selfUid) {
        continue;
      }
      if (blocked.contains(uid) ||
          liked.contains(uid) ||
          passed.contains(uid)) {
        continue;
      }
      if (!DiscoveryActivityPolicy.isEligible(
        lastActiveAtOf?.call(seed),
        now: clock?.call(),
      )) {
        continue;
      }
      final distance = kmOf(seed);
      final boosted = boostedUids?.contains(uid) == true;
      if (!expandDistance && distance != null) {
        final maxKm = boosted
            ? DiscoveryBoostRanking.effectiveRadiusKm(radiusKm, boosted: true)
            : radiusKm.toDouble();
        if (distance > maxKm) {
          // Soft-drop only when expand is off — matches legacy strict radius.
          // With expandDistance, far candidates fill empty decks.
          continue;
        }
        buckets[DiscoveryDistanceTier.nearby]!.add(seed);
        continue;
      }
      final tier = DiscoveryFallback.classify(
        distanceKm: distance,
        radiusKm: radiusKm,
        boosted: boosted,
      );
      buckets[tier]!.add(seed);
    }

    if (!expandDistance) {
      return buckets[DiscoveryDistanceTier.nearby]!;
    }
    return DiscoveryFallback.fillFromTiers(
      buckets: buckets,
      limit: limit ?? seeds.length,
    );
  }
}
