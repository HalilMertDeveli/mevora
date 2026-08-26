import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/matching/data/memory/graph_repositories.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';

/// In-memory social graph for development demo users.
///
/// Never written to production Firestore. Used so Like → Match → Chat works
/// when the other person is a local seed profile (`mock-*`).
class DemoSocialHub {
  DemoSocialHub({required this.uidSource})
    : graph = InMemorySocialGraph();

  final AuthUidSource uidSource;
  final InMemorySocialGraph graph;

  late final GraphMatchRepository matches = GraphMatchRepository(
    graph,
    uidSource,
  );
  late final GraphChatRepository chat = GraphChatRepository(graph, uidSource);

  static bool isDemoUid(String uid) => uid.startsWith('mock-');

  String? createMutualMatch({
    required String selfUid,
    required DiscoveryCandidate candidate,
    required String action,
  }) {
    if (selfUid.isEmpty || candidate.uid.isEmpty || selfUid == candidate.uid) {
      return null;
    }
    graph.seedProfile(selfUid, name: 'Sen');
    graph.seedProfile(
      candidate.uid,
      name: candidate.displayName,
      photoUrl: candidate.photoUrl,
    );
    final reverseId = MatchEngine.likeId(
      fromUserId: candidate.uid,
      toUserId: selfUid,
    );
    if (!graph.likes.containsKey(reverseId)) {
      graph.recordSwipe(
        actorUid: candidate.uid,
        targetUserId: selfUid,
        action: 'like',
      );
    }
    final forwardId = MatchEngine.likeId(
      fromUserId: selfUid,
      toUserId: candidate.uid,
    );
    if (!graph.likes.containsKey(forwardId)) {
      graph.recordSwipe(
        actorUid: selfUid,
        targetUserId: candidate.uid,
        action: action == 'superLike' ? 'superLike' : 'like',
      );
    }
    return MatchEngine.matchId(selfUid, candidate.uid);
  }
}
