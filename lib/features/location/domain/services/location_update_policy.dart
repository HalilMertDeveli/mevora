import 'package:mevora/core/geo/distance_calculator.dart';
import 'package:mevora/core/services/location/geo_position.dart';

/// Decides when to persist GPS. No continuous or background tracking.
class LocationUpdatePolicy {
  const LocationUpdatePolicy({
    this.meaningfulMoveMeters = 750,
    this.minInterval = const Duration(minutes: 10),
  });

  /// Spec range: 500 m–1 km. Default sits in the middle.
  final double meaningfulMoveMeters;
  final Duration minInterval;

  bool shouldWrite({
    required GeoPosition next,
    GeoPosition? lastPersisted,
    DateTime? now,
  }) {
    if (lastPersisted == null) {
      return true;
    }
    final clock = now ?? DateTime.now();
    if (clock.difference(lastPersisted.capturedAt) >= minInterval) {
      return true;
    }
    final movedMeters =
        DistanceCalculator.calculatePositions(lastPersisted, next) * 1000;
    return movedMeters >= meaningfulMoveMeters;
  }
}

class LocationSyncCoordinator {
  LocationSyncCoordinator({
    this.policy = const LocationUpdatePolicy(),
  });

  final LocationUpdatePolicy policy;
  GeoPosition? lastPersisted;

  bool shouldPersist(GeoPosition next) {
    return policy.shouldWrite(next: next, lastPersisted: lastPersisted);
  }

  void markPersisted(GeoPosition position) {
    lastPersisted = position;
  }
}
