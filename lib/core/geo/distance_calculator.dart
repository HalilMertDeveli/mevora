import 'dart:math' as math;

import 'package:mevora/core/services/location/geo_position.dart';

/// Haversine distance in kilometers. Domain-only; widgets never see coordinates.
abstract final class DistanceCalculator {
  static const double earthRadiusKm = 6371;

  static double calculate(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    if (!_isValid(lat1, lng1) || !_isValid(lat2, lng2)) {
      return double.nan;
    }
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double calculatePositions(GeoPosition a, GeoPosition b) {
    return calculate(a.latitude, a.longitude, b.latitude, b.longitude);
  }

  /// 0.4 km → 400 m; 1.2 km → 1.2 km.
  static String format(double kilometers) {
    if (kilometers.isNaN || kilometers.isNegative) {
      return '';
    }
    if (kilometers < 1) {
      final meters = (kilometers * 1000).round();
      return '$meters m';
    }
    final rounded = (kilometers * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return '${rounded.toStringAsFixed(0)} km';
    }
    return '${rounded.toStringAsFixed(1)} km';
  }

  static String formatAway(double kilometers) {
    final label = format(kilometers);
    if (label.isEmpty) {
      return '';
    }
    return '$label away';
  }

  static bool _isValid(double lat, double lng) {
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  static double _rad(double degrees) => degrees * math.pi / 180;
}
