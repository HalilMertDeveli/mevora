import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';

enum DiscoveryDecision { pass, like, superLike }

class DiscoveryPageResult {
  const DiscoveryPageResult({
    required this.candidates,
    this.nextCursor,
  });

  final List<DiscoveryCandidate> candidates;
  final String? nextCursor;
}

/// Server-backed discovery. Clients never download the full user collection.
abstract class DiscoveryRepository {
  Future<Result<DiscoveryPageResult>> getCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  });

  Future<Result<DiscoveryDecisionResult>> recordDecision({
    required String candidateUid,
    required DiscoveryDecision decision,
  });
}

/// Optional development-only deck reset. Production repositories omit this.
abstract class DemoDiscoverySupport {
  bool get supportsDemoRestart;

  void restartDemo();

  bool isExhaustedForRadius(int radiusKm);
}

class DiscoveryDecisionResult {
  const DiscoveryDecisionResult({this.matched = false, this.matchId});

  final bool matched;
  final String? matchId;
}
