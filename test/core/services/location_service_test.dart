import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/services/location_service.dart';
import 'package:mevora/features/location/data/repositories/location_repository_impl.dart';

import '../../helpers/fake_location_device.dart';

void main() {
  const logger = AppLogger(environment: AppEnvironment.development);

  LocationService buildService(FakeLocationDevice device) {
    return LocationService(device: device, logger: logger);
  }

  test('returns a position when GPS and permission are granted', () async {
    final device = FakeLocationDevice();
    final result = await buildService(device).getCurrentLocation();

    expect(result, isA<Success<GeoPosition>>());
    expect(result.valueOrNull?.latitude, 41.0082);
  });

  test('reports GPS disabled without requesting a fix', () async {
    final device = FakeLocationDevice(gpsEnabled: false);
    final result = await buildService(device).getCurrentLocation();

    expect(result, isA<Err<GeoPosition>>());
    final failure = (result as Err<GeoPosition>).failure as LocationFailure;
    expect(failure.kind, LocationErrorKind.gpsDisabled);
    expect(device.getCurrentPositionCalls, 0);
  });

  test('reports permission denied', () async {
    final device = FakeLocationDevice(
      permission: LocationPermissionStatus.denied,
    );
    final result = await buildService(device).getCurrentLocation();
    final failure = (result as Err<GeoPosition>).failure as LocationFailure;

    expect(failure.kind, LocationErrorKind.permissionDenied);
  });

  test('reports permanently denied permission', () async {
    final device = FakeLocationDevice(
      permission: LocationPermissionStatus.permanentlyDenied,
    );
    final result = await buildService(device).getCurrentLocation();
    final failure = (result as Err<GeoPosition>).failure as LocationFailure;

    expect(failure.kind, LocationErrorKind.permissionPermanentlyDenied);
  });

  test('maps a timeout from the device', () async {
    final device = FakeLocationDevice(
      failWith: const LocationException(
        'timed out',
        kind: LocationErrorKind.timeout,
      ),
    );
    final result = await buildService(device).getCurrentLocation();
    final failure = (result as Err<GeoPosition>).failure as LocationFailure;

    expect(failure.kind, LocationErrorKind.timeout);
  });

  test('maps an unexpected device error', () async {
    final device = FakeLocationDevice(failWith: Exception('sensor'));
    final result = await buildService(device).getCurrentLocation();
    final failure = (result as Err<GeoPosition>).failure as LocationFailure;

    expect(failure.kind, LocationErrorKind.error);
  });

  test('repository delegates capture to LocationService', () async {
    final device = FakeLocationDevice();
    final repository = LocationRepositoryImpl(
      locationService: buildService(device),
    );

    final result = await repository.captureCurrentLocation();
    expect(result.isSuccess, isTrue);
    expect(await repository.isGpsEnabled(), isTrue);
    expect(
      await repository.checkPermission(),
      LocationPermissionStatus.granted,
    );
  });
}
