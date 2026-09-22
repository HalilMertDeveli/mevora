import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/geo/geohash.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/entities/stored_user_location.dart';

class FirebaseLocationDataSource {
  FirebaseLocationDataSource({
    FirebaseFirestore? firestore,
    BackendCallable? backend,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _backend = backend;

  final FirebaseFirestore _firestore;
  final BackendCallable? _backend;

  /// Owner write only. Other clients never read this collection.
  Future<void> saveOwnerLocation({
    required String uid,
    required GeoPosition position,
  }) async {
    if (!position.isValid) {
      throw const LocationException(
        'Location is currently unavailable.',
        kind: LocationErrorKind.invalidCoordinates,
      );
    }
    try {
      await _firestore.collection(FirestorePaths.userLocation).doc(uid).set({
        'uid': uid,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'geohash': GeoHash.encode(position.latitude, position.longitude),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection(FirestorePaths.users).doc(uid).set({
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on LocationException {
      rethrow;
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebase(error), stackTrace);
    }
  }

  Future<StoredUserLocation?> loadOwnerLocation(String uid) async {
    try {
      final snap = await _firestore
          .collection(FirestorePaths.userLocation)
          .doc(uid)
          .get();
      if (!snap.exists) {
        return null;
      }
      final data = snap.data() ?? const <String, dynamic>{};
      final lat = firestoreDouble(data['latitude']);
      final lng = firestoreDouble(data['longitude']);
      if (lat == null || lng == null) {
        return null;
      }
      return StoredUserLocation(
        uid: uid,
        latitude: lat,
        longitude: lng,
        geohash: (data['geohash'] as String?) ?? '',
        updatedAt: firestoreDate(data['updatedAt']) ?? DateTime.now(),
      );
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebase(error), stackTrace);
    }
  }

  Future<void> clearOwnerLocation(String uid) async {
    try {
      await _firestore.collection(FirestorePaths.userLocation).doc(uid).delete();
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebase(error), stackTrace);
    }
  }

  Future<LocationFlags> loadLocationFlags(String uid) async {
    try {
      final snap = await _firestore
          .collection(FirestorePaths.userSettings)
          .doc(uid)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      return LocationFlags(
        uid: uid,
        locationEnabled: firestoreFlag(data['locationEnabled']),
        locationOnboardingCompleted: firestoreFlag(
          data['locationOnboardingCompleted'],
        ),
        lastLocationUpdate: firestoreDate(data['lastLocationUpdate']),
      );
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebase(error), stackTrace);
    }
  }

  Future<void> saveLocationFlags(LocationFlags flags) async {
    try {
      await _firestore
          .collection(FirestorePaths.userSettings)
          .doc(flags.uid)
          .set({
            'locationEnabled': flags.locationEnabled,
            'locationOnboardingCompleted': flags.locationOnboardingCompleted,
            if (flags.lastLocationUpdate != null)
              'lastLocationUpdate': Timestamp.fromDate(flags.lastLocationUpdate!),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebase(error), stackTrace);
    }
  }

  Future<DistanceLabel> distanceLabelTo(String otherUid) async {
    final backend = _backend;
    if (backend == null) {
      return const DistanceLabel(text: '');
    }
    try {
      final data = await backend.invoke('getDistanceLabel', {
        'otherUid': otherUid,
      });
      // The backend discloses a quantised band (bucketKm), never a raw
      // kilometre figure: a precise distance to a chosen user is a
      // trilateration oracle. Treat this value as approximate.
      return DistanceLabel(
        text: (data['label'] as String?) ?? '',
        kilometers: firestoreDouble(data['bucketKm']),
      );
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebase(error), stackTrace);
    }
  }

  LocationException _mapFirebase(FirebaseException error) {
    final network = error.code == 'unavailable' || error.code == 'network-request-failed';
    return LocationException(
      'Location is currently unavailable.',
      cause: error,
      kind: network ? LocationErrorKind.network : LocationErrorKind.error,
    );
  }
}
