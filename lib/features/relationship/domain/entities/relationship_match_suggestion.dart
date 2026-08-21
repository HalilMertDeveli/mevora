import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

/// Profile that shares relationship answers. Not an automatic mutual match.
class RelationshipMatchSuggestion {
  const RelationshipMatchSuggestion({
    required this.candidate,
    required this.score,
    required this.sharedQuestionCount,
    required this.alignedCount,
    this.topTopics = const [],
    this.matchId,
  });

  final DiscoveryCandidate candidate;
  final int score;
  final int sharedQuestionCount;
  final int alignedCount;
  final List<RelationshipTopic> topTopics;
  final String? matchId;
}
