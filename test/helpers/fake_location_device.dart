import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_device.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';

class FakeLocationDevice implements LocationDevice {
  FakeLocationDevice({
    this.gpsEnabled = true,
    this.permission = LocationPermissionStatus.granted,
    this.accuracy = LocationAccuracyKind.precise,
    GeoPosition? position,
    this.failWith,
    this.appSettingsOpened = false,
    this.gpsSettingsOpened = false,
  }) : position =
           position ??
           GeoPosition(
             latitude: 41.0082,
             longitude: 28.9784,
             capturedAt: DateTime.utc(2026, 8, 18),
           );

  bool gpsEnabled;
  LocationPermissionStatus permission;
  LocationAccuracyKind accuracy;
  GeoPosition position;
  Object? failWith;
  bool appSettingsOpened;
  bool gpsSettingsOpened;
  int requestPermissionCalls = 0;
  int getCurrentPositionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => gpsEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async => permission;

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    requestPermissionCalls += 1;
    return permission;
  }

  @override
  Future<GeoPosition> getCurrentPosition({required Duration timeout}) async {
    getCurrentPositionCalls += 1;
    final error = failWith;
    if (error != null) {
      throw error;
    }
    return position;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened = true;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    gpsSettingsOpened = true;
    return true;
  }

  @override
  Future<LocationAccuracyKind> checkAccuracy() async => accuracy;
}
