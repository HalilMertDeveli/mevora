import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';

LocationPermissionStatus toLocationPermissionStatus(PermissionStatus status) {
  return switch (status) {
    PermissionStatus.granted || PermissionStatus.limited =>
      LocationPermissionStatus.granted,
    PermissionStatus.denied => LocationPermissionStatus.denied,
    PermissionStatus.permanentlyDenied =>
      LocationPermissionStatus.permanentlyDenied,
    PermissionStatus.restricted => LocationPermissionStatus.restricted,
    PermissionStatus.unknown => LocationPermissionStatus.unknown,
  };
}
