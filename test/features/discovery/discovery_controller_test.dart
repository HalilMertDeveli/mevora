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
}
