import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/services/location/location_provider.dart';
import 'package:mevora/core/services/location_service.dart';
import 'package:mevora/features/location/data/datasources/firebase_location_data_source.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/entities/stored_user_location.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';

class LocationRepositoryImpl implements LocationRepository {
  LocationRepositoryImpl({
    required LocationService locationService,
    LocationProvider? locationProvider,
    FirebaseLocationDataSource? locationDataSource,
    AuthUidSource? uidSource,
  }) : _locationProvider = locationProvider ?? locationService,
       _locationDataSource = locationDataSource,
       _uidSource = uidSource;

  final LocationProvider _locationProvider;
  final FirebaseLocationDataSource? _locationDataSource;
  final AuthUidSource? _uidSource;

  @override
  Future<bool> isGpsEnabled() => _locationProvider.isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> checkPermission() {
    return _locationProvider.getPermissionStatus();
  }

  @override
  Future<LocationPermissionStatus> requestPermission() {
    return _locationProvider.requestPermission();
  }

  @override
  Future<Result<GeoPosition>> captureCurrentLocation() {
    return _locationProvider.getCurrentLocation();
  }

  @override
  Future<LocationAccuracyKind> checkAccuracy() {
    return _locationProvider.checkAccuracy();
  }

  @override
  Future<bool> openAppSettings() => _locationProvider.openAppSettings();

  @override
  Future<bool> openGpsSettings() => _locationProvider.openLocationSettings();

  @override
  Future<Result<void>> persistOwnerLocation({
    required String uid,
    required GeoPosition position,
  }) async {
    final denied = _rejectForeignUid(uid);
    if (denied != null) {
      return denied;
    }
    final source = _locationDataSource;
    if (source == null) {
      return const Err(
        LocationFailure(
          'Location persistence is not configured.',
          kind: LocationErrorKind.error,
        ),
      );
    }
    try {
      await source.saveOwnerLocation(uid: uid, position: position);
      return const Success(null);
    } on Object catch (error) {
      return _mapWriteError<void>(error);
    }
  }

  @override
  Future<Result<StoredUserLocation?>> loadOwnerLocation(String uid) async {
    final denied = _rejectForeignUid(uid);
    if (denied != null) {
      return Err(denied.failure);
    }
    final source = _locationDataSource;
    if (source == null) {
      return const Success(null);
    }
    try {
      return Success(await source.loadOwnerLocation(uid));
    } on Object catch (error) {
      return _mapWriteError<StoredUserLocation?>(error);
    }
  }

  @override
  Future<Result<void>> clearOwnerLocation(String uid) async {
    final denied = _rejectForeignUid(uid);
    if (denied != null) {
      return denied;
    }
    final source = _locationDataSource;
    if (source == null) {
      return const Err(
        LocationFailure(
          'Location persistence is not configured.',
          kind: LocationErrorKind.error,
        ),
      );
    }
    try {
      await source.clearOwnerLocation(uid);
      return const Success(null);
    } on Object catch (error) {
      return _mapWriteError<void>(error);
    }
  }

  @override
  Future<Result<LocationFlags>> loadLocationFlags(String uid) async {
    final denied = _rejectForeignUid(uid);
    if (denied != null) {
      return Err(denied.failure);
    }
    final source = _locationDataSource;
    if (source == null) {
      return Success(
        LocationFlags(uid: uid),
      );
    }
    try {
      return Success(await source.loadLocationFlags(uid));
    } on Object catch (error) {
      return _mapWriteError<LocationFlags>(error);
    }
  }

  @override
  Future<Result<void>> saveLocationFlags(LocationFlags flags) async {
    final denied = _rejectForeignUid(flags.uid);
    if (denied != null) {
      return denied;
    }
    final source = _locationDataSource;
    if (source == null) {
      return const Err(
        LocationFailure(
          'Location persistence is not configured.',
          kind: LocationErrorKind.error,
        ),
      );
    }
    try {
      await source.saveLocationFlags(flags);
      return const Success(null);
    } on Object catch (error) {
      return _mapWriteError<void>(error);
    }
  }

  @override
  Future<Result<DistanceLabel>> distanceLabelTo(String otherUid) async {
    final source = _locationDataSource;
    if (source == null) {
      return const Err(
        LocationFailure(
          'Distance lookup is not configured.',
          kind: LocationErrorKind.error,
        ),
      );
    }
    try {
      return Success(await source.distanceLabelTo(otherUid));
    } on Object catch (error) {
      return _mapWriteError<DistanceLabel>(error);
    }
  }

  Err<void>? _rejectForeignUid(String uid) {
    final current = _uidSource?.currentUid;
    if (current == null || current == uid) {
      return null;
    }
    return const Err(
      AuthzFailure('You cannot change another user’s location.'),
    );
  }

  Err<T> _mapWriteError<T>(Object error) {
    final failure = FailureMapper.from(error);
    if (failure is LocationFailure) {
      return Err(failure);
    }
    if (failure is NetworkFailure) {
      return const Err(
        LocationFailure(
          'Location is currently unavailable.',
          kind: LocationErrorKind.network,
        ),
      );
    }
    return const Err(
      LocationFailure(
        'Location is currently unavailable.',
        kind: LocationErrorKind.error,
      ),
    );
  }
}
