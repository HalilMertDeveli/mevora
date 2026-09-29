import 'dart:async';

import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/picks/data/mevora_picks_repository_impl.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/domain/repositories/mevora_picks_repository.dart';

/// One server Pick payload, in the exact shape `getMevoraPicks` returns.
Map<String, dynamic> pickPayload({
  required String uid,
  String name = 'Zeynep',
  int age = 25,
  String pickType = 'bestOverall',
  List<String> labels = const [],
  List<Map<String, dynamic>> reasons = const [],
  int rank = 0,
  int overall = 84,
  int? humorScore,
  List<String> humorTraits = const [],
  double? distanceKm,
}) {
  return {
    'uid': uid,
    'profile': {
      'uid': uid,
      'displayName': name,
      'age': age,
      'photos': const <Object>[],
      'interests': const ['hiking'],
      'city': 'İstanbul',
    },
    'distanceKm': distanceKm,
    'distanceLabel': null,
    'compatibilityScore': overall,
    'compatibilityBreakdown': {'overallScore': overall},
    'sharedInterests': const <String>[],
    'isBoosted': false,
    'pick': {
      'pickId': 'pick_$uid',
      'generationId': 'gen1',
      'pickType': pickType,
      'labels': labels.isEmpty ? [pickType] : labels,
      'reasons': reasons.isEmpty
          ? [
              {
                'type': 'overall',
                'score': overall,
                'strength': overall >= 78 ? 'strong' : 'notable',
                'meta': <String, Object>{},
              },
            ]
          : reasons,
      'rank': rank,
      'overallScore': overall,
      'humorCompatibilityScore': humorScore,
      'sharedHumorTraits': humorTraits,
    },
  };
}

MevoraPick pickFrom(Map<String, dynamic> payload) =>
    MevoraPicksParser.parsePick(payload, 'gen1')!;

MevoraPicksBatch batchOf(
  List<Map<String, dynamic>> picks, {
  String status = 'ready',
  String? emptyReason,
  Map<String, Object?>? learning,
}) {
  return MevoraPicksParser.parseBatch({
    'status': status,
    'emptyReason': emptyReason,
    'learning': ?learning,
    'generationId': 'gen1',
    'refreshAtMs': 1_900_000_000_000,
    'targetCount': 6,
    'picks': picks,
  });
}

/// Scriptable Picks backend for controller and widget tests.
class FakeMevoraPicksRepository implements MevoraPicksRepository {
  FakeMevoraPicksRepository(this.batch);

  MevoraPicksBatch batch;
  int loads = 0;
  final List<(String, DiscoveryDecision)> decisions = [];
  bool failDecisions = false;
  bool failLoads = false;
  bool matchOnLike = false;

  /// When set, decisions wait for this before answering.
  Completer<void>? gate;

  @override
  Future<Result<MevoraPicksBatch>> loadPicks() async {
    loads += 1;
    if (failLoads) {
      return const Err(NetworkFailure('offline'));
    }
    return Success(batch);
  }

  @override
  Future<Result<DiscoveryDecisionResult>> decide({
    required MevoraPick pick,
    required DiscoveryDecision decision,
  }) async {
    decisions.add((pick.uid, decision));
    await gate?.future;
    if (failDecisions) {
      return const Err(NetworkFailure('offline'));
    }
    final matched = matchOnLike && decision == DiscoveryDecision.like;
    return Success(
      DiscoveryDecisionResult(
        matched: matched,
        matchId: matched ? 'm_${pick.uid}' : null,
      ),
    );
  }
}
