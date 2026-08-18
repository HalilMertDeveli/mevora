import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';

/// Platform GPS access. Widgets must never call this directly.
abstract class LocationDevice {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermissionStatus> checkPermission();

  Future<LocationPermissionStatus> requestPermission();

  Future<GeoPosition> getCurrentPosition({required Duration timeout});

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();

  Future<LocationAccuracyKind> checkAccuracy();
}
