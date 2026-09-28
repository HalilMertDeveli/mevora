import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';

/// The candidate's scored compatibility signals, strongest first.
List<CompatibilitySignal> discoverySignals(
  DiscoveryCandidate candidate, {
  int? limit,
}) {
  return rankSignals({
    CompatibilitySignalKind.relationship: candidate.categoryRelationshipScore,
    CompatibilitySignalKind.lifestyle: candidate.categoryLifestyleScore,
    // The category weight only — the detailed music compatibility score is
    // shown after a mutual match, never on Discover.
    CompatibilitySignalKind.music: candidate.categoryMusicScore,
    CompatibilitySignalKind.questions: candidate.categoryQuestionScore,
    CompatibilitySignalKind.interests: candidate.categoryInterestScore,
    CompatibilitySignalKind.communication: candidate.categoryCommunicationScore,
  }, limit: limit);
}
