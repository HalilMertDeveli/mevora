import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/data/datasources/mock_discovery_data_source.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/domain/services/discovery_candidate_filter.dart';

/// Mock discovery for development and tests. Never touches Firestore.
class MockDiscoveryRepository
    implements DiscoveryRepository, DemoDiscoverySupport {
  MockDiscoveryRepository({
    this.selfUid = 'self',
    List<MockDiscoveryProfile>? profiles,
    this.demoHub,
    String Function()? currentUid,
    Set<String>? boostedUids,
  }) : _profiles = List<MockDiscoveryProfile>.from(
         profiles ?? MockDiscoveryDataSource.profiles(),
       ),
       _currentUid = currentUid,
       boostedUids = boostedUids ?? <String>{};

  final String selfUid;
  final DemoSocialHub? demoHub;
  final String Function()? _currentUid;
  final List<MockDiscoveryProfile> _profiles;
  final Set<String> blocked = <String>{};
  final Set<String> liked = <String>{};
  final Set<String> passed = <String>{};
  final Set<String> superLiked = <String>{};
  final Set<String> boostedUids;

  String get _actorUid => _currentUid?.call() ?? selfUid;

  @override
  bool get supportsDemoRestart => true;

  @override
  bool isExhaustedForRadius(int radiusKm) =>
      DiscoveryCandidateFilter.apply(
        seeds: _profiles,
        selfUid: _actorUid,
        blocked: blocked,
        liked: liked,
        passed: passed,
        radiusKm: radiusKm,
        uidOf: (seed) => seed.uid,
        distanceKmOf: (seed) => seed.distanceKm,
      ).isEmpty;

  @override
  void restartDemo() {
    liked.clear();
    passed.clear();
    superLiked.clear();
  }

  @override
  Future<Result<DiscoveryPageResult>> getCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  }) async {
    final visible = DiscoveryCandidateFilter.apply(
      seeds: _profiles,
      selfUid: _actorUid,
      blocked: blocked,
      liked: liked,
      passed: passed,
      radiusKm: radius.kilometers,
      uidOf: (seed) => seed.uid,
      distanceKmOf: (seed) => seed.distanceKm,
    );
    if (boostedUids.isNotEmpty) {
      visible.sort((a, b) {
        final aBoost = boostedUids.contains(a.uid) ? 1 : 0;
        final bBoost = boostedUids.contains(b.uid) ? 1 : 0;
        if (aBoost != bBoost) {
          return bBoost - aBoost;
        }
        return b.compatibilityScore.compareTo(a.compatibilityScore);
      });
    }
    final start = cursor == null
        ? 0
        : visible.indexWhere((seed) => seed.uid == cursor) + 1;
    final slice = visible.skip(start < 0 ? 0 : start).take(limit).toList();
    final candidates = slice.map(_toCandidate).toList();
    final next = start + slice.length < visible.length && slice.isNotEmpty
        ? slice.last.uid
        : null;
    return Success(
      DiscoveryPageResult(candidates: candidates, nextCursor: next),
    );
  }

  @override
  Future<Result<DiscoveryDecisionResult>> recordDecision({
    required String candidateUid,
    required DiscoveryDecision decision,
  }) async {
    final actor = _actorUid;
    if (candidateUid == actor) {
      return const Success(DiscoveryDecisionResult());
    }
    if (liked.contains(candidateUid) ||
        passed.contains(candidateUid) ||
        superLiked.contains(candidateUid)) {
      return const Success(DiscoveryDecisionResult());
    }
    switch (decision) {
      case DiscoveryDecision.pass:
        passed.add(candidateUid);
      case DiscoveryDecision.like:
        liked.add(candidateUid);
      case DiscoveryDecision.superLike:
        superLiked.add(candidateUid);
        liked.add(candidateUid);
    }

    if (decision == DiscoveryDecision.pass) {
      return const Success(DiscoveryDecisionResult());
    }

    MockDiscoveryProfile? seed;
    for (final profile in _profiles) {
      if (profile.uid == candidateUid) {
        seed = profile;
        break;
      }
    }
    if (seed == null || !seed.likesYou) {
      return const Success(DiscoveryDecisionResult());
    }

    final matchId = demoHub?.createMutualMatch(
      selfUid: actor,
      candidate: _toCandidate(seed),
      action: decision.name,
    );
    return Success(
      DiscoveryDecisionResult(matched: matchId != null, matchId: matchId),
    );
  }

  DiscoveryCandidate _toCandidate(MockDiscoveryProfile seed) {
    final profile = seed.profile;
    return DiscoveryCandidate(
      uid: seed.uid,
      displayName: profile.displayName,
      age: profile.resolvedAge,
      photos: profile.photos
          .map((photo) => photo.downloadUrl)
          .whereType<String>()
          .toList(),
      distanceLabel: seed.distanceLabel,
      distanceKm: seed.distanceKm,
      compatibilityScore: seed.compatibilityScore,
      interests: profile.interests,
      sharedInterests: seed.sharedInterests,
      compatibilityReasons: seed.compatibilityReasons,
      bio: profile.bio,
      city: profile.city,
      gender: profile.gender,
      relationshipGoal: profile.relationshipGoal,
      isDemo: true,
    );
  }
}
