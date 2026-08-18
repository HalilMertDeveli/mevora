import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/entities/stored_user_location.dart';

/// Location use-cases for features such as Discovery. Widgets depend on this
/// contract, never on GPS APIs or raw coordinates of other users.
abstract class LocationRepository {
  Future<bool> isGpsEnabled();

  Future<LocationPermissionStatus> checkPermission();

  Future<LocationPermissionStatus> requestPermission();

  Future<Result<GeoPosition>> captureCurrentLocation();

  Future<LocationAccuracyKind> checkAccuracy();

  Future<bool> openAppSettings();

  Future<bool> openGpsSettings();

  /// Writes the signed-in user's coordinates. Other clients cannot read them.
  Future<Result<void>> persistOwnerLocation({
    required String uid,
    required GeoPosition position,
  });

  Future<Result<StoredUserLocation?>> loadOwnerLocation(String uid);

  Future<Result<void>> clearOwnerLocation(String uid);

  Future<Result<LocationFlags>> loadLocationFlags(String uid);

  Future<Result<void>> saveLocationFlags(LocationFlags flags);

  /// Derived label from Cloud Functions. Never returns lat/lng of the other user.
  Future<Result<DistanceLabel>> distanceLabelTo(String otherUid);
}
