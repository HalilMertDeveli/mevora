import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_device.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/services/location/location_provider.dart';

/// Single GPS entry point. Presentation talks to [LocationRepository], never
/// to this service or to geolocator.
class LocationService implements LocationProvider {
  LocationService({
    required LocationDevice device,
    required AppLogger logger,
    this.timeout = const Duration(seconds: 8),
  }) : _device = device,
       _logger = logger;

  final LocationDevice _device;
  final AppLogger _logger;
  final Duration timeout;

  @override
  Future<bool> isLocationServiceEnabled() => _device.isLocationServiceEnabled();

  Future<bool> isGpsEnabled() => isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> getPermissionStatus() {
    return _device.checkPermission();
  }

  Future<LocationPermissionStatus> checkPermission() {
    return getPermissionStatus();
  }

  @override
  Future<LocationPermissionStatus> requestPermission() {
    return _device.requestPermission();
  }

  @override
  Future<bool> openAppSettings() => _device.openAppSettings();

  @override
  Future<bool> openLocationSettings() => _device.openLocationSettings();

  Future<bool> openGpsSettings() => openLocationSettings();

  @override
  Future<LocationAccuracyKind> checkAccuracy() => _device.checkAccuracy();

  @override
  Future<Result<GeoPosition>> getCurrentLocation() async {
    try {
      final gpsEnabled = await isLocationServiceEnabled();
      if (!gpsEnabled) {
        return const Err(
          LocationFailure(
            'Location services are turned off.',
            kind: LocationErrorKind.gpsDisabled,
          ),
        );
      }

      final permission = await getPermissionStatus();
      if (permission == LocationPermissionStatus.denied ||
          permission == LocationPermissionStatus.notDetermined) {
        return const Err(
          LocationFailure(
            'Location permission was denied.',
            kind: LocationErrorKind.permissionDenied,
          ),
        );
      }
      if (permission == LocationPermissionStatus.permanentlyDenied ||
          permission == LocationPermissionStatus.restricted) {
        return const Err(
          LocationFailure(
            'Location permission is permanently denied.',
            kind: LocationErrorKind.permissionPermanentlyDenied,
          ),
        );
      }
      if (permission != LocationPermissionStatus.granted) {
        return const Err(
          LocationFailure(
            'Location is currently unavailable.',
            kind: LocationErrorKind.unavailable,
          ),
        );
      }

      final position = await _device.getCurrentPosition(timeout: timeout);
      if (!position.isValid) {
        return const Err(
          LocationFailure(
            'Location is currently unavailable.',
            kind: LocationErrorKind.invalidCoordinates,
          ),
        );
      }
      return Success(position);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Failed to read current location',
        error: error,
        stackTrace: stackTrace,
      );
      final failure = FailureMapper.from(error);
      if (failure is LocationFailure) {
        return Err(failure);
      }
      return Err(
        LocationFailure(
          failure.message,
          kind: LocationErrorKind.error,
        ),
      );
    }
  }
}
