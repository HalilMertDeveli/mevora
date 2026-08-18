import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/entities/stored_user_location.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';

class FakeLocationRepository implements LocationRepository {
  FakeLocationRepository({
    this.gpsEnabled = true,
    this.permission = LocationPermissionStatus.granted,
    this.accuracy = LocationAccuracyKind.precise,
    this.currentUid,
    GeoPosition? position,
  }) : position =
           position ??
           GeoPosition(
             latitude: 41.0082,
             longitude: 28.9784,
             capturedAt: DateTime.utc(2026, 8, 18),
           );

  bool gpsEnabled;
  LocationPermissionStatus permission;
  LocationPermissionStatus requestResult = LocationPermissionStatus.granted;
  LocationAccuracyKind accuracy;
  GeoPosition position;
  String? currentUid;
  LocationFailure? captureFailure;
  LocationFailure? persistFailure;
  int requestPermissionCalls = 0;
  int persistCalls = 0;
  int captureCalls = 0;
  bool appSettingsOpened = false;
  bool gpsSettingsOpened = false;
  final Map<String, StoredUserLocation> stored = {};
  final Map<String, LocationFlags> flags = {};

  @override
  Future<bool> isGpsEnabled() async => gpsEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async => permission;

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    requestPermissionCalls += 1;
    permission = requestResult;
    return permission;
  }

  @override
  Future<Result<GeoPosition>> captureCurrentLocation() async {
    captureCalls += 1;
    if (!gpsEnabled) {
      return const Err(
        LocationFailure(
          'Location services are turned off.',
          kind: LocationErrorKind.gpsDisabled,
        ),
      );
    }
    if (permission != LocationPermissionStatus.granted) {
      return const Err(
        LocationFailure(
          'Location permission was denied.',
          kind: LocationErrorKind.permissionDenied,
        ),
      );
    }
    final forced = captureFailure;
    if (forced != null) {
      return Err(forced);
    }
    return Success(position);
  }

  @override
  Future<LocationAccuracyKind> checkAccuracy() async => accuracy;

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened = true;
    return true;
  }

  @override
  Future<bool> openGpsSettings() async {
    gpsSettingsOpened = true;
    return true;
  }

  @override
  Future<Result<void>> persistOwnerLocation({
    required String uid,
    required GeoPosition position,
  }) async {
    persistCalls += 1;
    if (currentUid != null && currentUid != uid) {
      return const Err(
        LocationFailure(
          'Location is currently unavailable.',
          kind: LocationErrorKind.error,
        ),
      );
    }
    final forced = persistFailure;
    if (forced != null) {
      return Err(forced);
    }
    stored[uid] = StoredUserLocation(
      uid: uid,
      latitude: position.latitude,
      longitude: position.longitude,
      geohash: 'fake',
      updatedAt: position.capturedAt,
    );
    return const Success(null);
  }

  @override
  Future<Result<StoredUserLocation?>> loadOwnerLocation(String uid) async {
    return Success(stored[uid]);
  }

  @override
  Future<Result<void>> clearOwnerLocation(String uid) async {
    stored.remove(uid);
    return const Success(null);
  }

  @override
  Future<Result<LocationFlags>> loadLocationFlags(String uid) async {
    return Success(flags[uid] ?? LocationFlags(uid: uid));
  }

  @override
  Future<Result<void>> saveLocationFlags(LocationFlags next) async {
    flags[next.uid] = next;
    return const Success(null);
  }

  @override
  Future<Result<DistanceLabel>> distanceLabelTo(String otherUid) async {
    return const Success(DistanceLabel(text: 'Nearby'));
  }
}
