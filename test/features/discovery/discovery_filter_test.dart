import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  InMemoryDiscoveryRepository repo() {
    return InMemoryDiscoveryRepository(
      seeds: const [
        DiscoverySeed(
          profile: UserProfile(uid: 'self', displayName: 'Me', age: 28),
          distanceKm: 0,
          distanceLabel: '0 m',
        ),
        DiscoverySeed(
          profile: UserProfile(
            uid: 'near',
            displayName: 'Ada',
            age: 27,
            interests: ['travel'],
          ),
          distanceKm: 3.8,
          distanceLabel: '3.8 km away',
        ),
        DiscoverySeed(
          profile: UserProfile(uid: 'far', displayName: 'Lin', age: 30),
          distanceKm: 80,
          distanceLabel: '80 km away',
        ),
        DiscoverySeed(
          profile: UserProfile(uid: 'blocked-user', displayName: 'X', age: 22),
          distanceKm: 2,
          distanceLabel: '2 km away',
        ),
      ],
    );
  }

  test('excludes self, blocked, liked, passed, and out-of-radius users', () async {
    final discovery = repo()
      ..blocked.add('blocked-user')
      ..liked.add('none')
      ..passed.add('none');

    final page = await discovery.getCandidates(radius: DiscoveryRadius.km10);
    final uids = page.valueOrNull!.candidates.map((c) => c.uid).toList();

    expect(uids, contains('near'));
    expect(uids, isNot(contains('self')));
    expect(uids, isNot(contains('far')));
    expect(uids, isNot(contains('blocked-user')));
    expect(
      page.valueOrNull!.candidates.every((c) => c.distanceLabel != null),
      isTrue,
    );
  });

  test('pass and like remove the person from later pages', () async {
    final discovery = repo();
    await discovery.recordDecision(
      candidateUid: 'near',
      decision: DiscoveryDecision.pass,
    );
    await discovery.recordDecision(
      candidateUid: 'far',
      decision: DiscoveryDecision.like,
    );
    final page = await discovery.getCandidates(radius: DiscoveryRadius.km100);
    final uids = page.valueOrNull!.candidates.map((c) => c.uid).toList();
    expect(uids, isNot(contains('near')));
    expect(uids, isNot(contains('far')));
  });

  test('candidates never carry latitude or longitude fields', () async {
    final discovery = repo();
    final page = await discovery.getCandidates(radius: DiscoveryRadius.km100);
    for (final candidate in page.valueOrNull!.candidates) {
      expect(candidate.toString(), isNot(contains('latitude')));
      expect(candidate.distanceLabel, isNot(contains('41.')));
    }
  });
}
