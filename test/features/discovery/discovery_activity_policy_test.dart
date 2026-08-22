import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/discovery/data/datasources/mock_discovery_data_source.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/data/repositories/mock_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/domain/services/discovery_activity_policy.dart';
import 'package:mevora/features/discovery/domain/services/discovery_candidate_filter.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

class _FixedUid implements AuthUidSource {
  const _FixedUid(this.currentUid);

  @override
  final String? currentUid;

  @override
  Stream<String?> watchUid() => Stream.value(currentUid);
}

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  MockDiscoveryProfile seed({
    required String uid,
    DateTime? lastActiveAt,
    bool likesYou = false,
  }) {
    return MockDiscoveryProfile(
      profile: UserProfile(
        uid: uid,
        displayName: uid,
        age: 27,
        lastActiveAt: lastActiveAt,
        isDiscoverable: true,
        profileCompleted: true,
      ),
      compatibilityScore: 80,
      sharedInterests: const ['music'],
      compatibilityReasons: const ['Shared interests'],
      distanceKm: 3,
      likesYou: likesYou,
    );
  }

  group('DiscoveryActivityPolicy (90-day window)', () {
    test('logged in today is visible', () {
      expect(
        DiscoveryActivityPolicy.isEligible(now, now: now),
        isTrue,
      );
    });

    test('1 month ago is visible', () {
      expect(
        DiscoveryActivityPolicy.isEligible(
          now.subtract(const Duration(days: 30)),
          now: now,
        ),
        isTrue,
      );
    });

    test('2 months 29 days is visible', () {
      expect(
        DiscoveryActivityPolicy.isEligible(
          now.subtract(const Duration(days: 89)),
          now: now,
        ),
        isTrue,
      );
    });

    test('exactly 90 days is visible', () {
      expect(
        DiscoveryActivityPolicy.isEligible(
          now.subtract(const Duration(days: 90)),
          now: now,
        ),
        isTrue,
      );
    });

    test('more than 3 months is hidden', () {
      expect(
        DiscoveryActivityPolicy.isEligible(
          now.subtract(const Duration(days: 91)),
          now: now,
        ),
        isFalse,
      );
    });

    test('inactive user who logs in again becomes visible', () {
      final stale = now.subtract(const Duration(days: 120));
      expect(
        DiscoveryActivityPolicy.isEligible(stale, now: now),
        isFalse,
      );
      expect(
        DiscoveryActivityPolicy.isEligible(now, now: now),
        isTrue,
      );
    });

    test('missing lastActiveAt (new user) is visible', () {
      expect(DiscoveryActivityPolicy.isEligible(null, now: now), isTrue);
    });
  });

  group('data-layer discovery filter', () {
    test('MockDiscoveryRepository hides inactive and keeps new users', () async {
      final repo = MockDiscoveryRepository(
        clock: () => now,
        profiles: [
          seed(uid: 'today', lastActiveAt: now),
          seed(uid: 'month', lastActiveAt: now.subtract(const Duration(days: 30))),
          seed(uid: 'almost', lastActiveAt: now.subtract(const Duration(days: 89))),
          seed(uid: 'stale', lastActiveAt: now.subtract(const Duration(days: 91))),
          seed(uid: 'new-user'),
        ],
      );

      final page = await repo.getCandidates(radius: DiscoveryRadius.km50);
      final uids = page.valueOrNull!.candidates.map((c) => c.uid).toList();

      expect(uids, containsAll(['today', 'month', 'almost', 'new-user']));
      expect(uids, isNot(contains('stale')));
    });

    test('re-login after 3+ months returns the user to the pool', () async {
      var lastActive = now.subtract(const Duration(days: 120));
      final profiles = [
        seed(uid: 'returning', lastActiveAt: lastActive),
      ];
      final hidden = await MockDiscoveryRepository(
        clock: () => now,
        profiles: profiles,
      ).getCandidates(radius: DiscoveryRadius.km50);
      expect(hidden.valueOrNull!.candidates, isEmpty);

      lastActive = now;
      final visible = await MockDiscoveryRepository(
        clock: () => now,
        profiles: [seed(uid: 'returning', lastActiveAt: lastActive)],
      ).getCandidates(radius: DiscoveryRadius.km50);
      expect(
        visible.valueOrNull!.candidates.map((c) => c.uid),
        contains('returning'),
      );
    });

    test('InMemoryDiscoveryRepository applies the same 90-day cutoff', () async {
      final repo = InMemoryDiscoveryRepository(
        clock: () => now,
        seeds: [
          DiscoverySeed(
            profile: UserProfile(
              uid: 'fresh',
              displayName: 'Ada',
              age: 27,
              lastActiveAt: now,
            ),
            distanceKm: 2,
          ),
          DiscoverySeed(
            profile: UserProfile(
              uid: 'gone',
              displayName: 'Lin',
              age: 28,
              lastActiveAt: now.subtract(const Duration(days: 100)),
            ),
            distanceKm: 2,
          ),
        ],
      );
      final page = await repo.getCandidates(radius: DiscoveryRadius.km10);
      final uids = page.valueOrNull!.candidates.map((c) => c.uid).toList();
      expect(uids, ['fresh']);
    });

    test('filter runs before results are returned, not as a UI hide', () {
      final visible = DiscoveryCandidateFilter.apply(
        seeds: [
          seed(uid: 'ok', lastActiveAt: now),
          seed(uid: 'stale', lastActiveAt: now.subtract(const Duration(days: 200))),
        ],
        selfUid: 'self',
        blocked: const {},
        liked: const {},
        passed: const {},
        radiusKm: 50,
        uidOf: (s) => s.uid,
        distanceKmOf: (s) => s.distanceKm,
        lastActiveAtOf: (s) => s.profile.lastActiveAt,
        clock: () => now,
      );
      expect(visible.map((s) => s.uid), ['ok']);
    });

    test('existing matches and messages are not deleted', () async {
      const uid = _FixedUid('user-1');
      final hub = DemoSocialHub(uidSource: uid);
      final elif = MockDiscoveryDataSource.profiles()
          .firstWhere((profile) => profile.uid == 'mock-01');
      final repo = MockDiscoveryRepository(
        selfUid: 'user-1',
        demoHub: hub,
        currentUid: () => 'user-1',
        clock: () => now,
        profiles: [elif],
      );
      final liked = await repo.recordDecision(
        candidateUid: 'mock-01',
        decision: DiscoveryDecision.like,
      );
      expect(liked.valueOrNull?.matched, isTrue);
      final matchId = liked.valueOrNull!.matchId!;
      expect(hub.graph.matches.containsKey(matchId), isTrue);
      final likesBefore = Set<String>.from(hub.graph.likes.keys);
      final matchesBefore = Set<String>.from(hub.graph.matches.keys);
      final messagesBefore = {
        for (final entry in hub.graph.messages.entries)
          entry.key: List<Object>.from(entry.value),
      };

      final inactiveRepo = MockDiscoveryRepository(
        selfUid: 'user-1',
        demoHub: hub,
        currentUid: () => 'user-1',
        clock: () => now,
        profiles: [
          elif.withLastActiveAt(now.subtract(const Duration(days: 100))),
        ],
      );
      final page = await inactiveRepo.getCandidates(radius: DiscoveryRadius.km50);
      expect(page.valueOrNull!.candidates, isEmpty);
      expect(hub.graph.matches.keys, matchesBefore);
      expect(hub.graph.likes.keys, likesBefore);
      expect(
        hub.graph.messages.map((key, value) => MapEntry(key, value.length)),
        messagesBefore.map((key, value) => MapEntry(key, value.length)),
      );
    });
  });
}
