import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  DiscoveryController build({
    FakeLocationRepository? location,
    InMemoryDiscoveryRepository? discovery,
  }) {
    return DiscoveryController(
      uid: 'self',
      locationRepository: location ?? FakeLocationRepository(),
      discoveryRepository:
          discovery ??
          InMemoryDiscoveryRepository(
            seeds: const [
              DiscoverySeed(
                profile: UserProfile(uid: 'ada', displayName: 'Ada', age: 27),
                distanceKm: 4,
                distanceLabel: '4 km away',
              ),
            ],
          ),
      skipExplanationIfAlreadyGranted: false,
    );
  }

  test('does not request GPS until the user opts in', () async {
    final location = FakeLocationRepository(
      permission: LocationPermissionStatus.denied,
    );
    final controller = build(location: location);
    await controller.start();
    expect(controller.state.phase, LocationPromptPhase.explanation);
    expect(location.requestPermissionCalls, 0);
  });

  test('denied permission still loads discovery without GPS', () async {
    final location = FakeLocationRepository(
      permission: LocationPermissionStatus.denied,
    );
    final controller = build(location: location);
    await controller.start();
    await controller.skipLocation();
    expect(controller.state.phase, LocationPromptPhase.ready);
    expect(controller.state.candidates, isNotEmpty);
  });

  test('gps disabled is a recoverable empty-phase, not a crash', () async {
    final location = FakeLocationRepository(gpsEnabled: false);
    final controller = build(location: location);
    await controller.useMyLocation();
    expect(controller.state.phase, LocationPromptPhase.gpsDisabled);
  });

  test('permanently denied explains settings', () async {
    final location = FakeLocationRepository(
      permission: LocationPermissionStatus.permanentlyDenied,
    );
    final controller = build(location: location);
    await controller.start();
    expect(controller.state.phase, LocationPromptPhase.permanentlyDenied);
  });

  test('radius changes reload candidates', () async {
    final controller = build();
    await controller.skipLocation();
    await controller.setRadius(DiscoveryRadius.km5);
    expect(controller.state.radius, DiscoveryRadius.km5);
  });

  test('hideCandidate removes profile from stack', () async {
    final discovery = InMemoryDiscoveryRepository(
      seeds: const [
        DiscoverySeed(
          profile: UserProfile(uid: 'ada', displayName: 'Ada', age: 27),
          distanceKm: 4,
          distanceLabel: '4 km away',
        ),
        DiscoverySeed(
          profile: UserProfile(uid: 'beo', displayName: 'Beo', age: 28),
          distanceKm: 6,
          distanceLabel: '6 km away',
        ),
      ],
    );
    final controller = build(discovery: discovery);
    await controller.skipLocation();
    expect(controller.state.candidates, hasLength(2));
    await controller.hideCandidate('ada');
    expect(controller.state.candidates, hasLength(1));
    expect(controller.state.candidates.first.uid, 'beo');
  });

  test('appends next page when deck runs low', () async {
    final seeds = List.generate(
      5,
      (index) => DiscoverySeed(
        profile: UserProfile(
          uid: 'user-$index',
          displayName: 'User $index',
          age: 25 + index,
        ),
        distanceKm: 3,
        distanceLabel: '3 km away',
      ),
    );
    final discovery = InMemoryDiscoveryRepository(seeds: seeds);
    final controller = build(discovery: discovery);
    await controller.skipLocation();
    expect(controller.state.candidates.length, lessThanOrEqualTo(5));
    final initialCount = controller.state.candidates.length;
    while (controller.state.candidates.length > 1) {
      await controller.onPass(controller.state.current!.uid);
    }
    expect(controller.state.candidates, isNotEmpty);
    if (initialCount < seeds.length) {
      await controller.onPass(controller.state.current!.uid);
      expect(controller.state.candidates, isNotEmpty);
    }
  });
}
