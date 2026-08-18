import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/domain/services/discovery_candidate_filter.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// In-memory backend stand-in for tests. Does not expose coordinates.
class InMemoryDiscoveryRepository implements DiscoveryRepository {
  InMemoryDiscoveryRepository({
    this.selfUid = 'self',
    List<DiscoverySeed>? seeds,
    CompatibilityEngine? engine,
  }) : _engine = engine ?? CompatibilityEngine.standard(),
       _seeds = List<DiscoverySeed>.from(seeds ?? const []);

  final String selfUid;
  final CompatibilityEngine _engine;
  final List<DiscoverySeed> _seeds;
  final Set<String> blocked = <String>{};
  final Set<String> liked = <String>{};
  final Set<String> passed = <String>{};
  final Set<String> likedByOther = <String>{};

  DiscoveryPreferences preferences = const DiscoveryPreferences();

  @override
  Future<Result<DiscoveryPageResult>> getCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  }) async {
    final visible = DiscoveryCandidateFilter.apply(
      seeds: _seeds,
      selfUid: selfUid,
      blocked: blocked,
      liked: liked,
      passed: passed,
      radiusKm: radius.kilometers,
    );
    final start = cursor == null
        ? 0
        : visible.indexWhere((seed) => seed.uid == cursor) + 1;
    final slice = visible.skip(start < 0 ? 0 : start).take(limit).toList();
    final viewer = UserProfile(
      uid: selfUid,
      displayName: 'You',
      age: 28,
      interests: const ['travel', 'music'],
      relationshipGoal: 'longTerm',
      lifestyle: const ['early-riser'],
    );
    final candidates = slice.map((seed) {
      final result = _engine.evaluate(
        CompatibilityContext(
          viewer: viewer,
          candidate: seed.profile,
          preferences: preferences.copyWith(maxDistanceKm: radius.kilometers.toDouble()),
          distanceKm: seed.distanceKm,
        ),
      );
      return DiscoveryCandidate(
        uid: seed.uid,
        displayName: seed.profile.displayName,
        age: seed.profile.resolvedAge,
        photoUrl: seed.profile.photos.isEmpty
            ? null
            : seed.profile.photos.first.downloadUrl,
        distanceLabel: seed.distanceLabel,
        distanceKm: seed.distanceKm,
        compatibilityScore: result.score,
        interests: seed.profile.interests,
        sharedInterests: result.sharedInterests,
        compatibilityReasons: result.reasons,
        bio: seed.profile.bio,
        city: seed.profile.city,
      );
    }).toList();
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
    if (decision == DiscoveryDecision.pass) {
      passed.add(candidateUid);
      return const Success(DiscoveryDecisionResult());
    }
    liked.add(candidateUid);
    final matched = likedByOther.contains(candidateUid);
    return Success(DiscoveryDecisionResult(matched: matched));
  }
}

class DiscoverySeed {
  const DiscoverySeed({
    required this.profile,
    this.distanceKm,
    this.distanceLabel,
  });

  final UserProfile profile;
  final double? distanceKm;
  final String? distanceLabel;

  String get uid => profile.uid;
}

extension on DiscoveryPreferences {
  DiscoveryPreferences copyWith({double? maxDistanceKm}) {
    return DiscoveryPreferences(
      minAge: minAge,
      maxAge: maxAge,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
    );
  }
}
