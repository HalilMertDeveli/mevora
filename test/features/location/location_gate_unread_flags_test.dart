import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';

/// A location repository whose flags read fails, the way Firestore does on a
/// cold start with no connection and `userSettings/{uid}` not in its cache.
class _UnreadableFlagsLocationRepository extends FakeLocationRepository {
  _UnreadableFlagsLocationRepository({super.permission});

  bool flagsReadable = false;
  int flagWrites = 0;

  @override
  Future<Result<LocationFlags>> loadLocationFlags(String uid) async {
    if (!flagsReadable) {
      return const Err(
        LocationFailure(
          'Location is currently unavailable.',
          kind: LocationErrorKind.network,
        ),
      );
    }
    return super.loadLocationFlags(uid);
  }

  @override
  Future<Result<void>> saveLocationFlags(LocationFlags next) {
    flagWrites += 1;
    return super.saveLocationFlags(next);
  }
}

/// The app-level location gate (the page a member meets before onboarding).
/// "Could not read the flags" used to count as "never asked": the gate came
/// up for a member who had answered long ago, and its "Skip for now" stored
/// locationEnabled: false over their choice.
void main() {
  LocationController build(FakeLocationRepository repository) {
    final controller = LocationController(
      repository: repository,
      successHold: Duration.zero,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('unreadable flags do not open the location gate', () async {
    final repository = _UnreadableFlagsLocationRepository(
      permission: LocationPermissionStatus.granted,
    );
    final controller = build(repository);

    await controller.syncForUser('u1');

    expect(controller.isResolved, isTrue);
    expect(controller.onboardingNeeded, isFalse);
    expect(repository.flagWrites, 0);
  });

  test('a member who was never asked still meets the gate when the flags '
      'can be read', () async {
    final repository = _UnreadableFlagsLocationRepository(
      permission: LocationPermissionStatus.notDetermined,
    )..flagsReadable = true;
    final controller = build(repository);

    await controller.syncForUser('u1');

    expect(controller.isResolved, isTrue);
    expect(controller.onboardingNeeded, isTrue);
  });

  test('a member who answered does not meet the gate', () async {
    final repository =
        _UnreadableFlagsLocationRepository(
            permission: LocationPermissionStatus.granted,
          )
          ..flagsReadable = true
          ..flags['u1'] = const LocationFlags(
            uid: 'u1',
            locationEnabled: true,
            locationOnboardingCompleted: true,
          );
    final controller = build(repository);

    await controller.syncForUser('u1');

    expect(controller.onboardingNeeded, isFalse);
  });
}
