import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';

/// Why Mevora chose someone. Stable API identifiers; the UI localises them.
enum PickType {
  bestOverall,
  valuesMatch,
  humorMatch,
  musicMatch,
  nearbyMatch,
  unexpectedMatch;

  static PickType? tryParse(Object? raw) {
    for (final value in PickType.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }
}

/// The dimension a single reason speaks to.
enum PickReasonType {
  overall('overall'),
  relationship('relationship'),

  /// Agreement on the relationship questions. API value `values`, which Dart
  /// reserves on enums.
  relationshipViews('values'),
  communication('communication'),
  lifestyle('lifestyle'),
  humor('humor'),
  music('music'),
  distance('distance'),
  interests('interests');

  const PickReasonType(this.apiValue);

  final String apiValue;

  static PickReasonType? tryParse(Object? raw) {
    for (final value in PickReasonType.values) {
      if (value.apiValue == raw) {
        return value;
      }
    }
    return null;
  }
}

enum PickReasonStrength { strong, notable }

/// One structured, server-computed reason. [score] is present only when the
/// server measured a real 0–100 score; copy must never invent one.
class PickReason {
  const PickReason({
    required this.type,
    this.score,
    this.strength = PickReasonStrength.notable,
    this.meta = const {},
  });

  final PickReasonType type;
  final int? score;
  final PickReasonStrength strength;

  /// Counts and category keys only.
  final Map<String, Object> meta;

  bool get isStrong => strength == PickReasonStrength.strong;

  int? intMeta(String key) {
    final value = meta[key];
    return value is num ? value.round() : null;
  }

  String? stringMeta(String key) {
    final value = meta[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  List<String> listMeta(String key) {
    final value = meta[key];
    return value is List ? value.whereType<String>().toList() : const [];
  }
}

/// A person Mevora selected for the viewer, with the reasons it chose them.
class MevoraPick {
  const MevoraPick({
    required this.candidate,
    required this.pickId,
    required this.generationId,
    required this.pickType,
    this.labels = const [],
    this.reasons = const [],
    this.rank = 0,
    this.overallScore = 0,
    this.humorScore,
    this.sharedHumorTraits = const [],
  });

  final DiscoveryCandidate candidate;

  /// Opaque id for analytics joins. Never the candidate's uid.
  final String pickId;
  final String generationId;

  /// The primary reason — the one the card leads with.
  final PickType pickType;

  /// Every category this person qualified for, most meaningful first.
  final List<PickType> labels;
  final List<PickReason> reasons;
  final int rank;
  final int overallScore;

  /// Real Humor Lab pair score, when both calibrated.
  final int? humorScore;
  final List<HumorCategory> sharedHumorTraits;

  String get uid => candidate.uid;

  /// Labels other than the primary one, for secondary chips.
  List<PickType> get secondaryLabels =>
      labels.where((label) => label != pickType).toList();

  PickReason? reasonOf(PickReasonType type) {
    for (final reason in reasons) {
      if (reason.type == type) {
        return reason;
      }
    }
    return null;
  }
}

enum PicksStatus { ready, lowSupply, empty }

enum PicksEmptyReason {
  allDecided,
  noCandidates,
  discoveryDisabled,

  /// A new member's first Picks wait for the initial learning questions.
  learningRequired,
}

class MevoraPicksBatch {
  const MevoraPicksBatch({
    required this.status,
    this.emptyReason,
    this.generationId,
    this.refreshAt,
    this.targetCount = 10,
    this.picks = const [],
    this.learning = LearningSummary.unknown,
  });

  static const MevoraPicksBatch empty = MevoraPicksBatch(
    status: PicksStatus.empty,
    emptyReason: PicksEmptyReason.noCandidates,
  );

  final PicksStatus status;
  final PicksEmptyReason? emptyReason;
  final String? generationId;
  final DateTime? refreshAt;

  /// The day's size, as the server chose it (PICKS_DAILY_TARGET). The
  /// default only covers a response that carries none.
  final int targetCount;
  final List<MevoraPick> picks;

  /// Where the member stands with Relationship Learning.
  final LearningSummary learning;

  MevoraPicksBatch copyWith({List<MevoraPick>? picks}) {
    final next = picks ?? this.picks;
    return MevoraPicksBatch(
      status: next.isEmpty ? PicksStatus.empty : status,
      emptyReason: next.isEmpty
          ? (emptyReason ?? PicksEmptyReason.allDecided)
          : emptyReason,
      generationId: generationId,
      refreshAt: refreshAt,
      targetCount: targetCount,
      picks: next,
      learning: learning,
    );
  }
}
