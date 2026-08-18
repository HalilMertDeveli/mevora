import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';

/// OS GPS port. Widgets and use cases never call this; [LocationRepository] does.
abstract class LocationProvider {
  Future<LocationPermissionStatus> requestPermission();

  Future<Result<GeoPosition>> getCurrentLocation();

  Future<LocationPermissionStatus> getPermissionStatus();

  Future<bool> openLocationSettings();

  Future<bool> openAppSettings();

  Future<bool> isLocationServiceEnabled();

  Future<LocationAccuracyKind> checkAccuracy();
}
