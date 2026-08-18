import 'dart:math' as math;

/// Compact geohash encoder used when the owner writes `userLocation/{uid}`.
/// Other clients never read this document.
abstract final class GeoHash {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  static String encode(
    double latitude,
    double longitude, {
    int precision = 9,
  }) {
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLng = -180.0;
    var maxLng = 180.0;
    final buffer = StringBuffer();
    var isLng = true;
    var bit = 0;
    var ch = 0;

    while (buffer.length < precision) {
      if (isLng) {
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch = (ch << 1) + 1;
          minLng = mid;
        } else {
          ch <<= 1;
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch = (ch << 1) + 1;
          minLat = mid;
        } else {
          ch <<= 1;
          maxLat = mid;
        }
      }
      isLng = !isLng;
      bit++;
      if (bit == 5) {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return buffer.toString();
  }
}

/// Haversine distance. Cloud Functions use this so other clients never
/// receive raw coordinates.
abstract final class GeoDistance {
  static const double _earthKm = 6371;

  static double km({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    final dLat = _rad(toLat - fromLat);
    final dLng = _rad(toLng - fromLng);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h =
        sinLat * sinLat +
        math.cos(_rad(fromLat)) * math.cos(_rad(toLat)) * sinLng * sinLng;
    final clamped = h.clamp(0.0, 1.0);
    return 2 * _earthKm * math.asin(math.sqrt(clamped));
  }

  /// Coarse UI string. Never expose exact meters.
  static String label(double kilometers) {
    if (kilometers < 1) {
      return 'Less than 1 km away';
    }
    if (kilometers >= 100) {
      return '100+ km away';
    }
    return '${kilometers.round()} km away';
  }

  /// Turkish coarse label used by discovery / `getDistanceLabel`.
  static String labelTr(double kilometers) {
    if (kilometers < 1) {
      return "1 km'den yakın";
    }
    if (kilometers >= 100) {
      return '100+ km uzakta';
    }
    return '${kilometers.round()} km uzakta';
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
