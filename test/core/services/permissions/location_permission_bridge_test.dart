import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/services/permissions/location_permission_bridge.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';

void main() {
  test('maps device permission statuses to location statuses', () {
    expect(
      toLocationPermissionStatus(PermissionStatus.granted),
      LocationPermissionStatus.granted,
    );
    expect(
      toLocationPermissionStatus(PermissionStatus.limited),
      LocationPermissionStatus.granted,
    );
    expect(
      toLocationPermissionStatus(PermissionStatus.denied),
      LocationPermissionStatus.denied,
    );
    expect(
      toLocationPermissionStatus(PermissionStatus.permanentlyDenied),
      LocationPermissionStatus.permanentlyDenied,
    );
    expect(
      toLocationPermissionStatus(PermissionStatus.restricted),
      LocationPermissionStatus.restricted,
    );
    expect(
      toLocationPermissionStatus(PermissionStatus.unknown),
      LocationPermissionStatus.unknown,
    );
  });
}
