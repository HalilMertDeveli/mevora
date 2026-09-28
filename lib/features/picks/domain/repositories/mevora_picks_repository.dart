import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';

/// Server-curated Mevora Picks. Selection, categories and reasons all come
/// from the backend; the client renders them and records decisions.
abstract class MevoraPicksRepository {
  /// The viewer's current batch. Safe to call on every screen open: a live
  /// batch comes back unchanged, only revalidated.
  Future<Result<MevoraPicksBatch>> loadPicks();

  /// Likes or passes a Pick through the same decision path as Discover, so a
  /// like from Picks is an ordinary like and a mutual one an ordinary match.
  Future<Result<DiscoveryDecisionResult>> decide({
    required MevoraPick pick,
    required DiscoveryDecision decision,
  });
}

/// Implemented by discovery repositories that can also serve Mevora Picks.
///
/// Demo and in-memory repositories do not: Picks are never padded with demo
/// or fabricated people, so without a real backend there are no Picks and
/// Discover works as before.
abstract class MevoraPicksCapable {
  MevoraPicksRepository? get picksRepository;
}
