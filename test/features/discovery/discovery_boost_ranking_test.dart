import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/domain/services/discovery_boost_ranking.dart';
import 'package:mevora/features/discovery/domain/services/discovery_candidate_filter.dart';

void main() {
  group('DiscoveryBoostRanking', () {
    const boosted = {'boost-user'};

    test('inactive boost keeps normal ranking', () {
      final normalScore = DiscoveryBoostRanking.rankScore(
        uid: 'normal',
        compatibilityScore: 80,
        musicRankingBonus: 5,
        distanceKm: 5,
        radiusKm: 25,
        boostedUids: boosted,
      );
      final inactiveBoostScore = DiscoveryBoostRanking.rankScore(
        uid: 'other',
        compatibilityScore: 60,
        musicRankingBonus: 0,
        distanceKm: 5,
        radiusKm: 25,
        boostedUids: boosted,
      );
      expect(normalScore, greaterThan(inactiveBoostScore));
    });

    test('active boost raises ranking priority', () {
      final normal = DiscoveryBoostRanking.rankScore(
        uid: 'normal',
        compatibilityScore: 70,
        musicRankingBonus: 0,
        distanceKm: null,
        radiusKm: 25,
        boostedUids: boosted,
      );
      final boostedScore = DiscoveryBoostRanking.rankScore(
        uid: 'boost-user',
        compatibilityScore: 70,
        musicRankingBonus: 0,
        distanceKm: null,
        radiusKm: 25,
        boostedUids: boosted,
      );
      expect(boostedScore, greaterThan(normal));
      expect(
        boostedScore - normal,
        DiscoveryBoostRanking.boostPriorityBonus,
      );
    });

    test('does not discount distance for boosted profiles', () {
      // Distance outranks the score, so a discount would let Boost jump an
      // unbounded compatibility gap. Boost widens eligibility instead.
      expect(
        DiscoveryBoostRanking.distanceRankContribution(20, 25),
        DiscoveryBoostRanking.distanceRankContribution(20, 25),
      );
      expect(
        DiscoveryBoostRanking.distanceRankContribution(20, 25),
        lessThan(DiscoveryBoostRanking.distanceRankContribution(5, 25)),
      );
    });

    test('withholds the advantage below the compatibility floor', () {
      final weak = DiscoveryBoostRanking.rankScore(
        uid: 'boost-user',
        compatibilityScore: DiscoveryBoostRanking.minCompatibility - 1,
        musicRankingBonus: 0,
        distanceKm: null,
        radiusKm: 25,
        boostedUids: boosted,
      );
      final weakUnboosted = DiscoveryBoostRanking.rankScore(
        uid: 'boost-user',
        compatibilityScore: DiscoveryBoostRanking.minCompatibility - 1,
        musicRankingBonus: 0,
        distanceKm: null,
        radiusKm: 25,
        boostedUids: const {},
      );
      expect(weak, weakUnboosted);
    });

    test('compatibility score is not modified by ranking helper', () {
      const compatibility = 42;
      DiscoveryBoostRanking.rankScore(
        uid: 'boost-user',
        compatibilityScore: compatibility,
        musicRankingBonus: 0,
        distanceKm: 8,
        radiusKm: 25,
        boostedUids: boosted,
      );
      expect(compatibility, 42);
    });

    test('expired boost returns to normal ranking', () {
      final active = DiscoveryBoostRanking.rankScore(
        uid: 'boost-user',
        compatibilityScore: 75,
        musicRankingBonus: 0,
        distanceKm: null,
        radiusKm: 25,
        boostedUids: boosted,
      );
      final expired = DiscoveryBoostRanking.rankScore(
        uid: 'boost-user',
        compatibilityScore: 75,
        musicRankingBonus: 0,
        distanceKm: null,
        radiusKm: 25,
        boostedUids: const {},
      );
      expect(active, greaterThan(expired));
      expect(
        active - expired,
        DiscoveryBoostRanking.boostPriorityBonus,
      );
    });

    test('spaces boosted profiles out with the density cap', () {
      final ranked = DiscoveryBoostRanking.sortCandidates(
        items: [
          const _Seed('b1', 90, 5),
          const _Seed('n1', 80, 5),
          const _Seed('b2', 70, 5),
          const _Seed('n2', 60, 5),
        ],
        boostedUids: const {'b1', 'b2'},
        radiusKm: 25,
        uidOf: (seed) => seed.uid,
        compatibilityOf: (seed) => seed.compatibility,
        musicBonusOf: (_) => 0,
        distanceOf: (seed) => seed.distanceKm,
      );
      // b1 leads on score; b2 is deferred so that no window of three
      // consecutive results holds more than one boosted profile.
      expect(ranked.map((seed) => seed.uid).toList(), ['b1', 'n1', 'n2', 'b2']);
    });
  });

  group('DiscoveryCandidateFilter boost radius', () {
    test('boosted profile stays eligible slightly beyond viewer radius', () {
      final seeds = [
        const _Seed('boost-user', 70, 28),
        const _Seed('normal-user', 70, 28),
      ];
      final visible = DiscoveryCandidateFilter.apply(
        seeds: seeds,
        selfUid: 'self',
        blocked: const {},
        liked: const {},
        passed: const {},
        radiusKm: 25,
        boostedUids: const {'boost-user'},
        uidOf: (seed) => seed.uid,
        distanceKmOf: (seed) => seed.distanceKm,
      );
      expect(visible.map((seed) => seed.uid), ['boost-user']);
    });

    test('blocked users remain excluded', () {
      const seeds = [
        _Seed('blocked-user', 70, 5),
      ];
      final visible = DiscoveryCandidateFilter.apply(
        seeds: seeds,
        selfUid: 'self',
        blocked: const {'blocked-user'},
        liked: const {},
        passed: const {},
        radiusKm: 100,
        boostedUids: const {'blocked-user'},
        uidOf: (seed) => seed.uid,
        distanceKmOf: (seed) => seed.distanceKm,
      );
      expect(visible, isEmpty);
    });
  });
}

class _Seed {
  const _Seed(this.uid, this.compatibility, this.distanceKm);

  final String uid;
  final int compatibility;
  final double distanceKm;
}
