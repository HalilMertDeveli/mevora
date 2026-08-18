import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/services/location_service.dart';
import 'package:mevora/features/location/data/repositories/location_repository_impl.dart';

import '../../helpers/fake_location_device.dart';

class _Uid implements AuthUidSource {
  _Uid(this.currentUid);

  @override
  final String? currentUid;

  @override
  Stream<String?> watchUid() => Stream<String?>.value(currentUid);
}

void main() {
  const logger = AppLogger(environment: AppEnvironment.development);
  final istanbul = GeoPosition(
    latitude: 41.0082,
    longitude: 28.9784,
    capturedAt: DateTime.utc(2026, 8, 18),
  );

  test('refuses to persist another user location', () async {
    final repo = LocationRepositoryImpl(
      locationService: LocationService(
        device: FakeLocationDevice(),
        logger: logger,
      ),
      uidSource: _Uid('owner'),
    );

    final result = await repo.persistOwnerLocation(
      uid: 'other',
      position: istanbul,
    );
    expect(result.isError, isTrue);
    expect(result.failureOrNull, isA<AuthzFailure>());
  });

  test('does not capture GPS when permission is denied', () async {
    final device = FakeLocationDevice(
      permission: LocationPermissionStatus.denied,
    );
    final repo = LocationRepositoryImpl(
      locationService: LocationService(device: device, logger: logger),
    );
    final result = await repo.captureCurrentLocation();
    expect(result.isError, isTrue);
    expect(device.getCurrentPositionCalls, 0);
  });

  test('opens location settings for GPS and app settings for denial', () async {
    final device = FakeLocationDevice();
    final repo = LocationRepositoryImpl(
      locationService: LocationService(device: device, logger: logger),
    );
    expect(await repo.openGpsSettings(), isTrue);
    expect(device.gpsSettingsOpened, isTrue);
    expect(await repo.openAppSettings(), isTrue);
    expect(device.appSettingsOpened, isTrue);
  });
}
