import 'package:mevora/features/discovery/domain/services/discovery_boost_ranking.dart';

/// Soft distance tiers used when preferred radius returns too few people.
enum DiscoveryDistanceTier {
  nearby,
  extended,
  far,
  noLocation,
}

abstract final class DiscoveryFallback {
  static const double extendedCapKm = 100;
  static const double farCapKm = 500;

  static const List<int> radiusLadderKm = [5, 10, 25, 50, 100];

  static DiscoveryDistanceTier classify({
    required double? distanceKm,
    required int radiusKm,
    required bool boosted,
  }) {
    if (distanceKm == null) {
      return DiscoveryDistanceTier.noLocation;
    }
    final nearbyMax = boosted
        ? DiscoveryBoostRanking.effectiveRadiusKm(radiusKm, boosted: true)
        : radiusKm.toDouble();
    if (distanceKm <= nearbyMax) {
      return DiscoveryDistanceTier.nearby;
    }
    final extended = radiusKm > extendedCapKm ? radiusKm.toDouble() : extendedCapKm;
    if (distanceKm <= extended) {
      return DiscoveryDistanceTier.extended;
    }
    return DiscoveryDistanceTier.far;
  }

  static int? nextRadiusKm(int currentKm) {
    final index = radiusLadderKm.indexOf(currentKm);
    if (index < 0) {
      return currentKm < 100 ? 100 : null;
    }
    if (index >= radiusLadderKm.length - 1) {
      return null;
    }
    return radiusLadderKm[index + 1];
  }

  /// Prefer nearby, then extended, far, then no-location — never drop all
  /// candidates solely for being outside the preferred radius.
  static List<T> fillFromTiers<T>({
    required Map<DiscoveryDistanceTier, List<T>> buckets,
    required int limit,
  }) {
    final order = [
      DiscoveryDistanceTier.nearby,
      DiscoveryDistanceTier.extended,
      DiscoveryDistanceTier.far,
      DiscoveryDistanceTier.noLocation,
    ];
    final out = <T>[];
    for (final tier in order) {
      for (final item in buckets[tier] ?? <T>[]) {
        if (out.length >= limit) {
          return out;
        }
        out.add(item);
      }
    }
    return out;
  }
}
