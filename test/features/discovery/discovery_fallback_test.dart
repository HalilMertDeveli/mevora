import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/domain/services/discovery_candidate_filter.dart';
import 'package:mevora/features/discovery/domain/services/discovery_fallback.dart';

class _Seed {
  const _Seed(this.uid, this.distanceKm);
  final String uid;
  final double? distanceKm;
}

void main() {
  group('DiscoveryFallback', () {
    test('classifies distance tiers', () {
      expect(
        DiscoveryFallback.classify(
          distanceKm: 5,
          radiusKm: 25,
          boosted: false,
        ),
        DiscoveryDistanceTier.nearby,
      );
      expect(
        DiscoveryFallback.classify(
          distanceKm: 80,
          radiusKm: 25,
          boosted: false,
        ),
        DiscoveryDistanceTier.extended,
      );
      expect(
        DiscoveryFallback.classify(
          distanceKm: 200,
          radiusKm: 25,
          boosted: false,
        ),
        DiscoveryDistanceTier.far,
      );
      expect(
        DiscoveryFallback.classify(
          distanceKm: null,
          radiusKm: 25,
          boosted: false,
        ),
        DiscoveryDistanceTier.noLocation,
      );
    });

    test('fills nearby before no-location', () {
      final filled = DiscoveryFallback.fillFromTiers(
        buckets: {
          DiscoveryDistanceTier.nearby: ['near'],
          DiscoveryDistanceTier.extended: ['ext'],
          DiscoveryDistanceTier.far: ['far'],
          DiscoveryDistanceTier.noLocation: ['noloc'],
        },
        limit: 3,
      );
      expect(filled, ['near', 'ext', 'far']);
    });

    test('radius ladder escalates to 100 then stops', () {
      expect(DiscoveryFallback.nextRadiusKm(25), 50);
      expect(DiscoveryFallback.nextRadiusKm(50), 100);
      expect(DiscoveryFallback.nextRadiusKm(100), isNull);
    });
  });

  group('DiscoveryCandidateFilter soft expand', () {
    final seeds = [
      const _Seed('near', 8),
      const _Seed('far', 180),
      const _Seed('noloc', null),
      const _Seed('self', 1),
    ];

    test('strict mode keeps only nearby', () {
      final visible = DiscoveryCandidateFilter.apply(
        seeds: seeds,
        selfUid: 'self',
        blocked: {},
        liked: {},
        passed: {},
        radiusKm: 25,
        expandDistance: false,
        uidOf: (s) => s.uid,
        distanceKmOf: (s) => s.distanceKm,
      );
      expect(visible.map((s) => s.uid), ['near']);
    });

    test('expand mode includes far and no-location after nearby', () {
      final visible = DiscoveryCandidateFilter.apply(
        seeds: seeds,
        selfUid: 'self',
        blocked: {},
        liked: {},
        passed: {},
        radiusKm: 25,
        expandDistance: true,
        limit: 10,
        uidOf: (s) => s.uid,
        distanceKmOf: (s) => s.distanceKm,
      );
      expect(visible.map((s) => s.uid).toList(), ['near', 'far', 'noloc']);
    });

    test('blocked users never appear even with expand', () {
      final visible = DiscoveryCandidateFilter.apply(
        seeds: seeds,
        selfUid: 'self',
        blocked: {'far'},
        liked: {},
        passed: {},
        radiusKm: 25,
        expandDistance: true,
        limit: 10,
        uidOf: (s) => s.uid,
        distanceKmOf: (s) => s.distanceKm,
      );
      expect(visible.map((s) => s.uid), isNot(contains('far')));
      expect(visible.map((s) => s.uid), isNot(contains('self')));
    });
  });
}
