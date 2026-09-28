import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/discovery/data/parsers/discovery_candidate_parser.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/picks/data/mevora_picks_repository_impl.dart';
import 'package:mevora/features/picks/domain/repositories/mevora_picks_repository.dart';

/// Calls privileged Cloud Functions. Never reads other users' coordinates.
class DiscoveryRepositoryImpl
    implements DiscoveryRepository, MevoraPicksCapable {
  DiscoveryRepositoryImpl({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  @override
  late final MevoraPicksRepository picksRepository = MevoraPicksRepositoryImpl(
    backend: _backend,
  );

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
            final candidate = DiscoveryCandidateParser.parse(
              Map<String, dynamic>.from(item),
            );
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
}
