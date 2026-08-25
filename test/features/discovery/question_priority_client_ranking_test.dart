import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_session_cache.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';

DiscoveryCandidate _c({
  required String uid,
  required int aligned,
  required double distanceKm,
  int compat = 50,
}) {
  return DiscoveryCandidate(
    uid: uid,
    displayName: uid,
    age: 25,
    photos: const [],
    distanceLabel: '${distanceKm}km',
    distanceKm: distanceKm,
    compatibilityScore: compat,
    compatibilityStatus: CompatibilityDisplayStatus.ready,
    interests: const [],
    sharedInterests: const [],
    compatibilityReasons: const [],
    relationshipAlignedCount: aligned,
  );
}

void main() {
  test('client ranking prefers 3/3 then closer distance', () {
    final ranked = DiscoveryRankingEngine.applyCompatibilityTiebreak([
      _c(uid: 'far-none', aligned: 0, distanceKm: 0.1, compat: 99),
      _c(uid: 'far-exact', aligned: 3, distanceKm: 8, compat: 60),
      _c(uid: 'near-exact', aligned: 3, distanceKm: 0.4, compat: 55),
    ]);
    expect(ranked.map((e) => e.uid).toList(), [
      'near-exact',
      'far-exact',
      'far-none',
    ]);
  });
}
