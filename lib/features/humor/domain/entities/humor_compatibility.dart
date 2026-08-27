import 'package:mevora/features/humor/domain/entities/humor_category.dart';

class HumorDifference {
  const HumorDifference({
    required this.dim,
    required this.a,
    required this.b,
  });

  final HumorCategory dim;
  final double a;
  final double b;
}

/// Match humor compatibility from `getMatchHumorCompatibility`.
/// Standalone MVP signal — not wired into Discover scoring.
class HumorCompatibility {
  const HumorCompatibility({
    required this.available,
    this.score,
    this.strongestShared = const [],
    this.differences = const [],
    this.confidence = 0,
    this.reason,
  });

  static const unavailable = HumorCompatibility(available: false);

  final bool available;
  final int? score;
  final List<HumorCategory> strongestShared;
  final List<HumorDifference> differences;
  final double confidence;
  final String? reason;

  bool get showDetails => available && score != null && score! > 0;
}
