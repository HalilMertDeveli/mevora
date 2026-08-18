import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_device.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';

class GeolocatorLocationDevice implements LocationDevice {
  const GeolocatorLocationDevice();

  @override
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    return _mapPermission(
      await Geolocator.checkPermission(),
      afterRequest: false,
    );
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    return _mapPermission(
      await Geolocator.requestPermission(),
      afterRequest: true,
    );
  }

  @override
  Future<GeoPosition> getCurrentPosition({required Duration timeout}) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
          distanceFilter: 100,
        ),
      );
      return GeoPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        capturedAt: position.timestamp,
        accuracyMeters: position.accuracy,
      );
    } on TimeoutException {
      throw const LocationException(
        'Location request timed out.',
        kind: LocationErrorKind.timeout,
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        'Location services are turned off.',
        kind: LocationErrorKind.gpsDisabled,
      );
    } on PermissionDeniedException {
      throw const LocationException(
        'Location permission was denied.',
        kind: LocationErrorKind.permissionDenied,
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        LocationException(
          'Location is currently unavailable.',
          cause: error,
          kind: LocationErrorKind.unavailable,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<LocationAccuracyKind> checkAccuracy() async {
    try {
      final status = await Geolocator.getLocationAccuracy();
      return switch (status) {
        LocationAccuracyStatus.precise => LocationAccuracyKind.precise,
        LocationAccuracyStatus.reduced => LocationAccuracyKind.reduced,
        _ => LocationAccuracyKind.unknown,
      };
    } on Object {
      return LocationAccuracyKind.unknown;
    }
  }

  LocationPermissionStatus _mapPermission(
    LocationPermission permission, {
    required bool afterRequest,
  }) {
    return switch (permission) {
      LocationPermission.always || LocationPermission.whileInUse =>
        LocationPermissionStatus.granted,
      LocationPermission.denied => afterRequest
          ? LocationPermissionStatus.denied
          : LocationPermissionStatus.notDetermined,
      LocationPermission.deniedForever =>
        LocationPermissionStatus.permanentlyDenied,
      LocationPermission.unableToDetermine => LocationPermissionStatus.unknown,
    };
  }
}
