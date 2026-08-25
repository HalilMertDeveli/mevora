import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';

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
    bool expandDistance = false,
  }) async {
    try {
      final data = await _backend.invoke('getDiscoveryCandidates', {
        'radiusKm': radius.kilometers,
        'cursor': cursor,
        'limit': limit,
        'expandDistance': expandDistance,
        if (kDebugMode) 'includeDebug': true,
      });
      final debug = data['debug'];
      if (kDebugMode && debug is Map) {
        developer.log(
          'discovery_debug ${Map<String, dynamic>.from(debug)}',
          name: 'DiscoveryRepository',
        );
      }
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

    final photosRaw = profile['photos'];
    final photoUrls = <String>[];
    if (photosRaw is List) {
      for (final item in photosRaw) {
        if (item is String) {
          photoUrls.add(item);
        } else if (item is Map) {
          final url =
              item['thumbUrl'] as String? ?? item['downloadUrl'] as String?;
          if (url != null) {
            photoUrls.add(url);
          }
        }
      }
    }
    final legacyPhoto = profile['photoUrl'] as String?;
    if (photoUrls.isEmpty && legacyPhoto != null) {
      photoUrls.add(legacyPhoto);
    }

    final breakdownRaw = raw['compatibilityBreakdown'];
    final breakdown = breakdownRaw is Map
        ? Map<String, dynamic>.from(breakdownRaw)
        : const <String, dynamic>{};

    final compatibilityScore = _parseCompatibilityScore(raw, breakdown);

    return DiscoveryCandidate(
      uid: uid,
      displayName: (profile['displayName'] as String?) ?? '',
      age: firestoreInt(profile['age'], 0),
      photos: photoUrls,
      distanceLabel: raw['distanceLabel'] as String?,
      distanceKm: firestoreDouble(raw['distanceKm']),
      compatibilityScore: compatibilityScore,
      compatibilityStatus: compatibilityScore > 0
          ? CompatibilityDisplayStatus.ready
          : CompatibilityDisplayStatus.calculating,
      interests: firestoreStringList(profile['interests']),
      languages: firestoreStringList(profile['languages']),
      hobbies: firestoreStringList(profile['hobbies']),
      lifestyle: firestoreStringList(profile['lifestyle']),
      lifestyleProfile: ProfileLifestyle.fromMap(
        profile['lifestyleProfile'] ?? profile['lifestyle'],
      ),
      sharedInterests: firestoreStringList(raw['sharedInterests']),
      compatibilityReasons: firestoreStringList(raw['compatibilityReasons']),
      bio: profile['bio'] as String?,
      city: profile['city'] as String?,
      gender: profile['gender'] as String?,
      relationshipGoal: profile['relationshipGoal'] as String?,
      musicCompatibilityScore: raw['musicCompatibilityScore'] == null
          ? null
          : firestoreInt(raw['musicCompatibilityScore'], 0),
      sharedMusicTracks: firestoreStringList(raw['sharedMusicTracks']),
      sharedMusicArtists: firestoreStringList(raw['sharedMusicArtists']),
      sharedMusicGenres: firestoreStringList(raw['sharedMusicGenres']),
      sharedMusicTrackCount: raw['sharedMusicTrackCount'] == null
          ? null
          : firestoreInt(raw['sharedMusicTrackCount'], 0),
      sharedMusicArtistCount: raw['sharedMusicArtistCount'] == null
          ? null
          : firestoreInt(raw['sharedMusicArtistCount'], 0),
      sharedMusicGenreCount: raw['sharedMusicGenreCount'] == null
          ? null
          : firestoreInt(raw['sharedMusicGenreCount'], 0),
      sharedMusicPlaylistTrackCount:
          raw['sharedMusicPlaylistTrackCount'] == null
          ? null
          : firestoreInt(raw['sharedMusicPlaylistTrackCount'], 0),
      sharedMusicRecentTrackCount: raw['sharedMusicRecentTrackCount'] == null
          ? null
          : firestoreInt(raw['sharedMusicRecentTrackCount'], 0),
      musicInsights: _parseMusicInsights(raw['musicInsights']),
      relationshipCompatibilityScore:
          raw['relationshipCompatibilityScore'] == null
          ? null
          : firestoreInt(raw['relationshipCompatibilityScore'], 0),
      relationshipSharedViewCount: raw['relationshipSharedViewCount'] == null
          ? null
          : firestoreInt(raw['relationshipSharedViewCount'], 0),
      relationshipAlignedCount: raw['relationshipAlignedCount'] == null
          ? null
          : firestoreInt(raw['relationshipAlignedCount'], 0),
      relationshipSummaryTopics: firestoreStringList(
        raw['relationshipSummaryTopics'],
      ),
      isVerified: profile['isVerified'] == true || raw['isVerified'] == true,
      isBoosted: raw['isBoosted'] == true,
      categoryRelationshipScore: breakdown['relationshipScore'] == null
          ? null
          : firestoreInt(breakdown['relationshipScore'], 0),
      categoryInterestScore: breakdown['interestScore'] == null
          ? null
          : firestoreInt(breakdown['interestScore'], 0),
      categoryLifestyleScore: breakdown['lifestyleScore'] == null
          ? null
          : firestoreInt(breakdown['lifestyleScore'], 0),
      categoryQuestionScore: breakdown['questionScore'] == null
          ? null
          : firestoreInt(breakdown['questionScore'], 0),
      categoryMusicScore: breakdown['musicScore'] == null
          ? null
          : firestoreInt(breakdown['musicScore'], 0),
      categoryCommunicationScore: breakdown['communicationScore'] == null
          ? null
          : firestoreInt(breakdown['communicationScore'], 0),
    );
  }

  int _parseCompatibilityScore(
    Map<String, dynamic> raw,
    Map<String, dynamic> breakdown,
  ) {
    final topLevel = firestoreInt(raw['compatibilityScore'], -1);
    if (topLevel > 0) {
      return topLevel;
    }
    final fromBreakdown = firestoreInt(breakdown['overallScore'], -1);
    if (fromBreakdown > 0) {
      return fromBreakdown;
    }
    return 0;
  }

  List<MusicInsight> _parseMusicInsights(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final out = <MusicInsight>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final code = MusicCompatibilityCalculator.parseInsightCode(
        map['code'] as String?,
      );
      final paramsRaw = map['params'];
      final params = <String, Object>{};
      if (paramsRaw is Map) {
        paramsRaw.forEach((key, value) {
          if (key is! String || value == null) {
            return;
          }
          if (value is int) {
            params[key] = value;
          } else if (value is double) {
            params[key] = value;
          } else if (value is String) {
            params[key] = value;
          } else if (value is num) {
            params[key] = value.toDouble();
          } else {
            params[key] = value.toString();
          }
        });
      }
      out.add(MusicInsight(code: code, params: params));
    }
    return out;
  }
}
