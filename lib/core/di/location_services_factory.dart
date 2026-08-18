import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/identity/firebase_auth_uid_source.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/location/geolocator_location_device.dart';
import 'package:mevora/core/services/location/location_device.dart';
import 'package:mevora/core/services/location_service.dart';
import 'package:mevora/features/location/data/datasources/firebase_location_data_source.dart';
import 'package:mevora/features/location/data/repositories/location_repository_impl.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';

class LocationServices {
  const LocationServices({
    required this.locationService,
    required this.locationRepository,
  });

  final LocationService locationService;
  final LocationRepository locationRepository;
}

LocationServices createLocationServices({
  LocationDevice? device,
  AppLogger? logger,
  AuthUidSource? uidSource,
  FirebaseLocationDataSource? locationDataSource,
}) {
  final locationService = LocationService(
    device: device ?? const GeolocatorLocationDevice(),
    logger: logger ?? const AppLogger(environment: AppEnvironment.development),
  );
  return LocationServices(
    locationService: locationService,
    locationRepository: LocationRepositoryImpl(
      locationService: locationService,
      locationDataSource:
          locationDataSource ??
          FirebaseLocationDataSource(
            backend: FirebaseFunctionsCallable(),
          ),
      uidSource: uidSource ?? FirebaseAuthUidSource(),
    ),
  );
}
