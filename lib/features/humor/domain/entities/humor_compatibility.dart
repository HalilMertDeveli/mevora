import 'package:mevora/features/humor/domain/entities/humor_category.dart';

/// How strongly two people's humor overlaps, as shown to them.
///
/// Three buckets rather than a number: the score is built from a small number
/// of ratings on each side, and "83%" would claim a precision it does not
/// have. It also says nothing about the relationship itself.
enum HumorCompatibilityLevel { low, medium, high }

/// Match humor compatibility from `getMatchHumorCompatibility`.
///
/// Mirrors the callable payload exactly: `{available, score, strongestShared,
/// reason}`. The server never returns the peer's vector or confidence, and
/// this entity has nowhere to put them. Standalone signal — not wired into
/// Discover or the main compatibility engine.
class HumorCompatibility {
  const HumorCompatibility({
    required this.available,
    this.score,
    this.strongestShared = const [],
    this.reason,
  });

  static const unavailable = HumorCompatibility(available: false);

  /// Either side has not finished the initial humor profile yet.
  static const reasonBuilding = 'building';

  /// Both finished, but at least one profile carries no real signal.
  static const reasonNoSignal = 'no-signal';

  /// The match is malformed (not exactly two members).
  static const reasonInvalidMatch = 'invalid-match';

  /// Score at or above which the pair reads as a high humor match.
  static const highThreshold = 70;

  /// Score at or above which the pair reads as a moderate humor match.
  static const mediumThreshold = 50;

  final bool available;

  /// 0–100. Kept for bucketing only; never shown to users as a number.
  final int? score;

  /// Humor styles both people lean into, strongest first.
  final List<HumorCategory> strongestShared;
  final String? reason;

  /// There is a real pair reading to show.
  bool get hasResult => available && score != null;

  /// Not enough data on one or both sides yet.
  bool get isBuilding => !available && reason == reasonBuilding;

  HumorCompatibilityLevel? get level => hasResult ? levelOf(score!) : null;

  static HumorCompatibilityLevel levelOf(int score) {
    if (score >= highThreshold) {
      return HumorCompatibilityLevel.high;
    }
    if (score >= mediumThreshold) {
      return HumorCompatibilityLevel.medium;
    }
    return HumorCompatibilityLevel.low;
  }
}
