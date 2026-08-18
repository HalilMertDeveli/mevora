import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/entities/stored_user_location.dart';
import 'package:mevora/features/location/domain/location_onboarding_gate.dart';
import 'package:mevora/features/location/domain/services/location_update_policy.dart';
import 'package:mevora/features/location/domain/usecases/location_usecases.dart';

void main() {
  final istanbul = GeoPosition(
    latitude: 41.0082,
    longitude: 28.9784,
    capturedAt: DateTime.utc(2026, 8, 18),
  );

  test('gate hides the screen when location already exists', () {
    expect(
      LocationOnboardingGate.shouldShow(
        locationOnboardingCompleted: false,
        hasStoredLocation: true,
      ),
      isFalse,
    );
  });

  test('gate hides the screen after the flow completed once', () {
    expect(
      LocationOnboardingGate.shouldShow(
        locationOnboardingCompleted: true,
        hasStoredLocation: false,
      ),
      isFalse,
    );
  });

  test('gate shows the screen for a new user without location', () {
    expect(
      LocationOnboardingGate.shouldShow(
        locationOnboardingCompleted: false,
        hasStoredLocation: false,
      ),
      isTrue,
    );
  });

  test('request permission does not open the dialog when GPS is off', () async {
    final repo = FakeLocationRepository(gpsEnabled: false);
    final result = await RequestLocationPermission(repo)();
    expect(result, isA<Err<LocationPermissionStatus>>());
    final failure = (result as Err<LocationPermissionStatus>).failure;
    expect(failure, isA<LocationFailure>());
    expect((failure as LocationFailure).kind, LocationErrorKind.gpsDisabled);
    expect(repo.requestPermissionCalls, 0);
  });

  test('request permission skips the OS dialog when denied forever', () async {
    final repo = FakeLocationRepository(
      permission: LocationPermissionStatus.permanentlyDenied,
    );
    final result = await RequestLocationPermission(repo)();
    expect(result.valueOrNull, LocationPermissionStatus.permanentlyDenied);
    expect(repo.requestPermissionCalls, 0);
  });

  test('request permission asks the OS when not determined', () async {
    final repo = FakeLocationRepository(
      permission: LocationPermissionStatus.notDetermined,
    )..requestResult = LocationPermissionStatus.granted;
    final result = await RequestLocationPermission(repo)();
    expect(result.valueOrNull, LocationPermissionStatus.granted);
    expect(repo.requestPermissionCalls, 1);
  });

  test('get current location returns a fix when granted', () async {
    final repo = FakeLocationRepository(position: istanbul);
    final result = await GetCurrentLocation(repo)();
    expect(result.valueOrNull?.latitude, istanbul.latitude);
  });

  test('save user location persists owner coords and flags', () async {
    final repo = FakeLocationRepository(currentUid: 'u1');
    final result = await SaveUserLocation(repo)(
      uid: 'u1',
      position: istanbul,
    );
    expect(result.isSuccess, isTrue);
    expect(repo.persistCalls, 1);
    expect(repo.stored['u1']?.latitude, istanbul.latitude);
    expect(repo.flags['u1']?.locationEnabled, isTrue);
    expect(repo.flags['u1']?.locationOnboardingCompleted, isTrue);
  });

  test('save user location rejects invalid coordinates', () async {
    final repo = FakeLocationRepository();
    final result = await SaveUserLocation(repo)(
      uid: 'u1',
      position: GeoPosition(
        latitude: 200,
        longitude: 28,
        capturedAt: DateTime.utc(2026, 8, 18),
      ),
    );
    expect(
      (result.failureOrNull as LocationFailure).kind,
      LocationErrorKind.invalidCoordinates,
    );
    expect(repo.persistCalls, 0);
  });

  test('update user location skips a nearby recent write', () async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final repo = FakeLocationRepository(
      position: istanbul,
      currentUid: 'u1',
    );
    repo.stored['u1'] = StoredUserLocation(
      uid: 'u1',
      latitude: istanbul.latitude,
      longitude: istanbul.longitude,
      geohash: 'sxk',
      updatedAt: now.subtract(const Duration(minutes: 2)),
    );
    final updated = await UpdateUserLocation(
      repo,
      clock: () => now,
    )(uid: 'u1');
    expect(updated.valueOrNull, isFalse);
    expect(repo.persistCalls, 0);
  });

  test('update user location writes after the time threshold', () async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final repo = FakeLocationRepository(
      position: istanbul,
      currentUid: 'u1',
    );
    repo.stored['u1'] = StoredUserLocation(
      uid: 'u1',
      latitude: istanbul.latitude,
      longitude: istanbul.longitude,
      geohash: 'sxk',
      updatedAt: now.subtract(const Duration(minutes: 20)),
    );
    final updated = await UpdateUserLocation(
      repo,
      clock: () => now,
    )(uid: 'u1');
    expect(updated.valueOrNull, isTrue);
    expect(repo.persistCalls, 1);
  });

  test('policy requires a meaningful move or the time threshold', () {
    const policy = LocationUpdatePolicy();
    final now = DateTime.utc(2026, 8, 18, 12);
    final last = GeoPosition(
      latitude: 41.0082,
      longitude: 28.9784,
      capturedAt: now.subtract(const Duration(minutes: 1)),
    );
    expect(
      policy.shouldWrite(
        next: GeoPosition(
          latitude: 41.0083,
          longitude: 28.9785,
          capturedAt: DateTime.utc(2026, 8, 18, 12),
        ),
        lastPersisted: last,
        now: now,
      ),
      isFalse,
    );
    expect(
      policy.shouldWrite(
        next: GeoPosition(
          latitude: 41.02,
          longitude: 28.99,
          capturedAt: DateTime.utc(2026, 8, 18, 12),
        ),
        lastPersisted: last,
        now: now,
      ),
      isTrue,
    );
  });

  test('get permission status reports GPS off as serviceDisabled', () async {
    final repo = FakeLocationRepository(gpsEnabled: false);
    expect(
      await GetLocationPermissionStatus(repo)(),
      LocationPermissionStatus.serviceDisabled,
    );
  });

  test('flags load defaults for a new user', () async {
    final repo = FakeLocationRepository();
    final flags = await repo.loadLocationFlags('u1');
    expect(flags.valueOrNull, isA<LocationFlags>());
    expect(flags.valueOrNull?.locationOnboardingCompleted, isFalse);
  });
}
