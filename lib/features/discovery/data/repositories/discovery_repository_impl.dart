import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

/// Calls privileged Cloud Functions. Never reads other users' coordinates.
class DiscoveryRepositoryImpl implements DiscoveryRepository {
  DiscoveryRepositoryImpl({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  @override
  Future<Result<DiscoveryPageResult>> getCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  }) async {
    try {
      final data = await _backend.invoke('getDiscoveryCandidates', {
        'radiusKm': radius.kilometers,
        'cursor': cursor,
        'limit': limit,
      });
      final rawItems = data['items'];
      final items = <DiscoveryCandidate>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            final candidate = _parseCandidate(Map<String, dynamic>.from(item));
            if (candidate != null) {
              items.add(candidate);
            }
          }
        }
      }
      return Success(
        DiscoveryPageResult(
          candidates: items,
          nextCursor: data['nextCursor'] as String?,
        ),
      );
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<DiscoveryDecisionResult>> recordDecision({
    required String candidateUid,
    required DiscoveryDecision decision,
  }) async {
    try {
      final data = await _backend.invoke('recordDiscoveryDecision', {
        'candidateUid': candidateUid,
        'action': decision.name,
      });
      return Success(
        DiscoveryDecisionResult(
          matched: data['matched'] == true,
          matchId: data['matchId'] as String?,
        ),
      );
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  DiscoveryCandidate? _parseCandidate(Map<String, dynamic> raw) {
    final uid = raw['uid'] as String?;
    if (uid == null || uid.isEmpty) {
      return null;
    }
    final profile = raw['profile'] is Map
        ? Map<String, dynamic>.from(raw['profile'] as Map)
        : raw;
    // Defense in depth: drop any accidental coordinate fields.
    profile.remove('latitude');
    profile.remove('longitude');
    profile.remove('geohash');
    raw.remove('latitude');
    raw.remove('longitude');
    raw.remove('geohash');

    final photos = profile['photos'];
    String? photoUrl;
    if (photos is List && photos.isNotEmpty) {
      final first = photos.first;
      if (first is String) {
        photoUrl = first;
      } else if (first is Map) {
        photoUrl =
            first['downloadUrl'] as String? ?? first['thumbUrl'] as String?;
      }
    }

    return DiscoveryCandidate(
      uid: uid,
      displayName: (profile['displayName'] as String?) ?? '',
      age: firestoreInt(profile['age'], 0),
      photoUrl: photoUrl ?? profile['photoUrl'] as String?,
      distanceLabel: raw['distanceLabel'] as String?,
      distanceKm: firestoreDouble(raw['distanceKm']),
      compatibilityScore: firestoreInt(raw['compatibilityScore'], 0),
      interests: firestoreStringList(profile['interests']),
      sharedInterests: firestoreStringList(raw['sharedInterests']),
      compatibilityReasons: firestoreStringList(raw['compatibilityReasons']),
      bio: profile['bio'] as String?,
      city: profile['city'] as String?,
    );
  }
}
