import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/data/repositories/mock_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

/// Development discovery: real Firestore/Functions candidates first, then
/// local demo profiles so the deck is never empty. Demo users are never
/// written to production Firebase.
class HybridDiscoveryRepository
    implements DiscoveryRepository, DemoDiscoverySupport {
  HybridDiscoveryRepository({
    required DiscoveryRepository remote,
    required MockDiscoveryRepository local,
    required this.allowDemoFallback,
    required String Function() currentUid,
  }) : _remote = remote,
       _local = local,
       _currentUid = currentUid;

  final DiscoveryRepository _remote;
  final MockDiscoveryRepository _local;
  final bool allowDemoFallback;
  final String Function() _currentUid;

  @override
  bool get supportsDemoRestart => allowDemoFallback;

  @override
  void restartDemo() => _local.restartDemo();

  @override
  bool isExhaustedForRadius(int radiusKm) =>
      _local.isExhaustedForRadius(radiusKm);

  @override
  Future<Result<DiscoveryPageResult>> getCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  }) async {
    final uid = _currentUid();
    final remoteResult = await _remote.getCandidates(
      radius: radius,
      cursor: cursor,
      limit: limit,
    );

    final demo = allowDemoFallback
        ? await _demoCandidates(radius: radius, cursor: cursor, limit: limit)
        : const <DiscoveryCandidate>[];

    if (remoteResult.isSuccess) {
      final page = remoteResult.valueOrNull!;
      final real = page.candidates
          .where((candidate) => candidate.uid != uid)
          .where((candidate) => !DemoSocialHub.isDemoUid(candidate.uid))
          .toList();
      if (!allowDemoFallback) {
        return Success(
          DiscoveryPageResult(candidates: real, nextCursor: page.nextCursor),
        );
      }
      final realIds = real.map((candidate) => candidate.uid).toSet();
      final merged = [
        ...real,
        ...demo.where((candidate) => !realIds.contains(candidate.uid)),
      ];
      return Success(
        DiscoveryPageResult(
          candidates: merged.take(limit).toList(),
          nextCursor: page.nextCursor,
        ),
      );
    }

    if (allowDemoFallback && demo.isNotEmpty) {
      return Success(
        DiscoveryPageResult(candidates: demo.take(limit).toList()),
      );
    }
    return remoteResult;
  }

  Future<List<DiscoveryCandidate>> _demoCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  }) async {
    final result = await _local.getCandidates(
      radius: radius,
      cursor: cursor,
      limit: 20,
    );
    final uid = _currentUid();
    return result.valueOrNull?.candidates
            .where((candidate) => candidate.uid != uid)
            .map(
              (candidate) => DiscoveryCandidate(
                uid: candidate.uid,
                displayName: candidate.displayName,
                age: candidate.age,
                photos: candidate.photos,
                distanceLabel: candidate.distanceLabel,
                distanceKm: candidate.distanceKm,
                compatibilityScore: candidate.compatibilityScore,
                compatibilityStatus: candidate.compatibilityStatus,
                interests: candidate.interests,
                sharedInterests: candidate.sharedInterests,
                compatibilityReasons: candidate.compatibilityReasons,
                bio: candidate.bio,
                city: candidate.city,
                gender: candidate.gender,
                relationshipGoal: candidate.relationshipGoal,
                musicCompatibilityScore: candidate.musicCompatibilityScore,
                relationshipCompatibilityScore:
                    candidate.relationshipCompatibilityScore,
                relationshipSharedViewCount:
                    candidate.relationshipSharedViewCount,
                relationshipAlignedCount: candidate.relationshipAlignedCount,
                relationshipSummaryTopics: candidate.relationshipSummaryTopics,
                isDemo: true,
              ),
            )
            .toList() ??
        const [];
  }

  @override
  Future<Result<DiscoveryDecisionResult>> recordDecision({
    required String candidateUid,
    required DiscoveryDecision decision,
  }) async {
    if (DemoSocialHub.isDemoUid(candidateUid)) {
      return _local.recordDecision(
        candidateUid: candidateUid,
        decision: decision,
      );
    }
    if (_currentUid() == candidateUid) {
      return const Success(DiscoveryDecisionResult());
    }
    return _remote.recordDecision(
      candidateUid: candidateUid,
      decision: decision,
    );
  }
}

/// Used when Functions are unavailable and development must still show cards.
class FallbackOnlyDiscoveryRepository
    implements DiscoveryRepository, DemoDiscoverySupport {
  FallbackOnlyDiscoveryRepository(this._local);

  final MockDiscoveryRepository _local;

  @override
  bool get supportsDemoRestart => true;

  @override
  void restartDemo() => _local.restartDemo();

  @override
  bool isExhaustedForRadius(int radiusKm) =>
      _local.isExhaustedForRadius(radiusKm);

  @override
  Future<Result<DiscoveryPageResult>> getCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  }) {
    return _local.getCandidates(radius: radius, cursor: cursor, limit: limit);
  }

  @override
  Future<Result<DiscoveryDecisionResult>> recordDecision({
    required String candidateUid,
    required DiscoveryDecision decision,
  }) {
    return _local.recordDecision(
      candidateUid: candidateUid,
      decision: decision,
    );
  }
}
