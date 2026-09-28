import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';
import 'package:mevora/features/location/domain/services/location_update_policy.dart';

class RequestLocationPermission {
  const RequestLocationPermission(this._repository);

  final LocationRepository _repository;

  Future<Result<LocationPermissionStatus>> call() async {
    final gpsEnabled = await _repository.isGpsEnabled();
    if (!gpsEnabled) {
      return const Err(
        LocationFailure(
          'Location services are turned off.',
          kind: LocationErrorKind.gpsDisabled,
        ),
      );
    }

    final current = await _repository.checkPermission();
    if (current.isDeniedForever) {
      return Success(current);
    }

    final next = await _repository.requestPermission();
    return Success(next);
  }
}

class GetCurrentLocation {
  const GetCurrentLocation(this._repository);

  final LocationRepository _repository;

  Future<Result<GeoPosition>> call() {
    return _repository.captureCurrentLocation();
  }
}

class GetLocationPermissionStatus {
  const GetLocationPermissionStatus(this._repository);

  final LocationRepository _repository;

  Future<LocationPermissionStatus> call() async {
    try {
      final gpsEnabled = await _repository.isGpsEnabled();
      if (!gpsEnabled) {
        return LocationPermissionStatus.serviceDisabled;
      }
      return await _repository.checkPermission();
    } on Object {
      return LocationPermissionStatus.error;
    }
  }
}

class SaveUserLocation {
  const SaveUserLocation(this._repository);

  final LocationRepository _repository;

  Future<Result<void>> call({
    required String uid,
    required GeoPosition position,
  }) async {
    if (uid.isEmpty) {
      return const Err(
        LocationFailure(
          'Location is currently unavailable.',
          kind: LocationErrorKind.error,
        ),
      );
    }
    if (!position.isValid) {
      return const Err(
        LocationFailure(
          'Location is currently unavailable.',
          kind: LocationErrorKind.invalidCoordinates,
        ),
      );
    }

    final persisted = await _repository.persistOwnerLocation(
      uid: uid,
      position: position,
    );
    if (persisted.isError) {
      return persisted;
    }

    return _repository.saveLocationFlags(
      LocationFlags(
        uid: uid,
        locationEnabled: true,
        locationOnboardingCompleted: true,
        lastLocationUpdate: position.capturedAt,
      ),
    );
  }
}

class UpdateUserLocation {
  UpdateUserLocation(
    this._repository, {
    this.policy = const LocationUpdatePolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocationRepository _repository;
  final LocationUpdatePolicy policy;
  final DateTime Function() _clock;

  /// Returns whether a Firestore write happened.
  Future<Result<bool>> call({
    required String uid,
    bool force = false,
  }) async {
    if (uid.isEmpty) {
      return const Err(
        LocationFailure(
          'Location is currently unavailable.',
          kind: LocationErrorKind.error,
        ),
      );
    }

    final captured = await _repository.captureCurrentLocation();
    final position = captured.valueOrNull;
    if (position == null) {
      return Err(
        captured.failureOrNull ??
            const LocationFailure(
              'Location is currently unavailable.',
              kind: LocationErrorKind.unavailable,
            ),
      );
    }

    final previousResult = await _repository.loadOwnerLocation(uid);
    if (previousResult.isError) {
      return Err(
        previousResult.failureOrNull ??
            const LocationFailure(
              'Location is currently unavailable.',
              kind: LocationErrorKind.error,
            ),
      );
    }

    final previous = previousResult.valueOrNull;
    GeoPosition? lastPersisted;
    if (previous != null) {
      lastPersisted = GeoPosition(
        latitude: previous.latitude,
        longitude: previous.longitude,
        capturedAt: previous.updatedAt,
      );
    }
    if (!force &&
        !policy.shouldWrite(
          next: position,
          lastPersisted: lastPersisted,
          now: _clock(),
        )) {
      return const Success(false);
    }

    final saved = await SaveUserLocation(_repository)(
      uid: uid,
      position: position,
    );
    if (saved.isError) {
      return Err(
        saved.failureOrNull ??
            const LocationFailure(
              'Location is currently unavailable.',
              kind: LocationErrorKind.error,
            ),
      );
    }
    return const Success(true);
  }
}
