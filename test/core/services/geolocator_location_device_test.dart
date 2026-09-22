import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/services/location/geolocator_location_device.dart';
import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';

Position _position({required DateTime timestamp, double latitude = 39.92}) {
  return Position(
    latitude: latitude,
    longitude: 32.85,
    timestamp: timestamp,
    accuracy: 12,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({this.current, this.lastKnown});

  /// Position to return, or null to time out like a stationary device.
  final Position? current;
  final Position? lastKnown;

  LocationSettings? capturedSettings;
  int currentCalls = 0;
  int lastKnownCalls = 0;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    currentCalls += 1;
    capturedSettings = locationSettings;
    final position = current;
    if (position == null) {
      throw TimeoutException('no fix');
    }
    return position;
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async {
    lastKnownCalls += 1;
    return lastKnown;
  }
}

class _StubPermissions implements PermissionService {
  @override
  Future<PermissionStatus> check(PermissionType type) async => PermissionStatus.granted;

  @override
  Future<PermissionStatus> request(PermissionType type) async => PermissionStatus.granted;

  @override
  Future<bool> isPermanentlyDenied(PermissionType type) async => false;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<Map<PermissionType, PermissionStatus>> checkAll() async => const {};
}

void main() {
  late GeolocatorPlatform original;

  setUp(() => original = GeolocatorPlatform.instance);
  tearDown(() => GeolocatorPlatform.instance = original);

  GeolocatorLocationDevice deviceWith(_FakeGeolocatorPlatform platform) {
    GeolocatorPlatform.instance = platform;
    return GeolocatorLocationDevice(permissions: _StubPermissions());
  }

  test('one-shot request does not set a displacement filter', () async {
    // A distanceFilter becomes Android's smallestDisplacement, so a stationary
    // device never receives a fix and onboarding times out.
    final platform = _FakeGeolocatorPlatform(
      current: _position(timestamp: DateTime.now().toUtc()),
    );
    final device = deviceWith(platform);

    final position = await device.getCurrentPosition(
      timeout: const Duration(seconds: 8),
    );

    expect(position.latitude, 39.92);
    expect(platform.capturedSettings, isNotNull);
    expect(platform.capturedSettings!.distanceFilter, 0);
    expect(platform.capturedSettings!.timeLimit, const Duration(seconds: 8));
  });

  test('falls back to a recent cached fix when the fresh request times out', () async {
    final platform = _FakeGeolocatorPlatform(
      lastKnown: _position(
        timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
        latitude: 41.01,
      ),
    );
    final device = deviceWith(platform);

    final position = await device.getCurrentPosition(
      timeout: const Duration(seconds: 8),
    );

    expect(position.latitude, 41.01);
    expect(platform.lastKnownCalls, 1);
  });

  test('ignores a stale cached fix and reports the timeout', () async {
    final platform = _FakeGeolocatorPlatform(
      lastKnown: _position(
        timestamp: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
      ),
    );
    final device = deviceWith(platform);

    await expectLater(
      device.getCurrentPosition(timeout: const Duration(seconds: 8)),
      throwsA(
        isA<LocationException>().having(
          (e) => e.kind,
          'kind',
          LocationErrorKind.timeout,
        ),
      ),
    );
  });

  test('reports the timeout when no cached fix exists', () async {
    final platform = _FakeGeolocatorPlatform();
    final device = deviceWith(platform);

    await expectLater(
      device.getCurrentPosition(timeout: const Duration(seconds: 8)),
      throwsA(
        isA<LocationException>().having(
          (e) => e.kind,
          'kind',
          LocationErrorKind.timeout,
        ),
      ),
    );
    expect(platform.lastKnownCalls, 1);
  });

  test('a cached-fix lookup failure still surfaces the timeout', () async {
    final device = deviceWith(_ThrowingLastKnownPlatform());

    await expectLater(
      device.getCurrentPosition(timeout: const Duration(seconds: 8)),
      throwsA(isA<LocationException>()),
    );
  });
}

class _ThrowingLastKnownPlatform extends _FakeGeolocatorPlatform {
  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) {
    throw const LocationServiceDisabledException();
  }
}
