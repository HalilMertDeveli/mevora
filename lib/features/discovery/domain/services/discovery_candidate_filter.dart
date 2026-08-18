/// Backend-style exclusion + radius filtering. Used by the in-memory
/// discovery stand-in and unit tests so the client never scans every user.
abstract final class DiscoveryCandidateFilter {
  static List<T> apply<T extends Object>({
    required List<T> seeds,
    required String selfUid,
    required Set<String> blocked,
    required Set<String> liked,
    required Set<String> passed,
    required int radiusKm,
    String Function(T seed)? uidOf,
    double? Function(T seed)? distanceKmOf,
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

    return seeds.where((seed) {
      final uid = idOf(seed);
      if (uid == selfUid) {
        return false;
      }
      if (blocked.contains(uid) || liked.contains(uid) || passed.contains(uid)) {
        return false;
      }
      final distance = kmOf(seed);
      if (distance != null && distance > radiusKm) {
        return false;
      }
      return true;
    }).toList();
  }
}
