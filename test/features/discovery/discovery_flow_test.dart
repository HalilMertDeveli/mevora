import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  test('login-ready user can skip GPS and still swipe discovery', () async {
    final location = FakeLocationRepository(
      permission: LocationPermissionStatus.denied,
    );
    final discovery = InMemoryDiscoveryRepository(
      seeds: const [
        DiscoverySeed(
          profile: UserProfile(
            uid: 'ada',
            displayName: 'Ada',
            age: 27,
            interests: ['travel'],
            relationshipGoal: 'longTerm',
          ),
          distanceKm: 3.8,
          distanceLabel: '3.8 km away',
        ),
      ],
    );
    final controller = DiscoveryController(
      uid: 'self',
      locationRepository: location,
      discoveryRepository: discovery,
      skipExplanationIfAlreadyGranted: false,
    );

    await controller.start();
    expect(controller.state.phase, LocationPromptPhase.explanation);

    await controller.useMyLocation();
    expect(controller.state.candidates, isNotEmpty);
    expect(controller.state.current?.distanceLabel, '3.8 km away');
    expect(controller.state.current?.compatibilityScore, greaterThan(0));

    await controller.decide(DiscoveryDecision.like);
    expect(discovery.liked, contains('ada'));
  });
}
