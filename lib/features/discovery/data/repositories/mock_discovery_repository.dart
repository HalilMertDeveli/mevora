import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/data/datasources/mock_discovery_data_source.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/domain/services/discovery_candidate_filter.dart';

/// Mock discovery for development and tests. Never touches Firestore.
class MockDiscoveryRepository implements DiscoveryRepository {
  MockDiscoveryRepository({
    this.selfUid = 'self',
    List<MockDiscoveryProfile>? profiles,
  }) : _profiles = List<MockDiscoveryProfile>.from(
         profiles ?? MockDiscoveryDataSource.profiles(),
       );

  final String selfUid;
  final List<MockDiscoveryProfile> _profiles;
  final Set<String> blocked = <String>{};
  final Set<String> liked = <String>{};
  final Set<String> passed = <String>{};
  final Set<String> superLiked = <String>{};

  bool isExhaustedForRadius(int radiusKm) =>
      DiscoveryCandidateFilter.apply(
        seeds: _profiles,
        selfUid: selfUid,
        blocked: blocked,
        liked: liked,
        passed: passed,
        radiusKm: radiusKm,
        uidOf: (seed) => seed.uid,
        distanceKmOf: (seed) => seed.distanceKm,
      ).isEmpty;

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
      selfUid: selfUid,
      blocked: blocked,
      liked: liked,
      passed: passed,
      radiusKm: radius.kilometers,
      uidOf: (seed) => seed.uid,
      distanceKmOf: (seed) => seed.distanceKm,
    );
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
    if (candidateUid == selfUid) {
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
    return const Success(DiscoveryDecisionResult());
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
    );
  }
}
