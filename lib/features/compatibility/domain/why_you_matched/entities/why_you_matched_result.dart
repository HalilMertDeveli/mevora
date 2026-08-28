import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';

/// Aggregated output of the Why You Matched engine for one pair.
class WhyYouMatchedResult {
  const WhyYouMatchedResult({
    required this.available,
    required this.reasons,
    this.overallScore,
    this.insufficientReason,
  });

  final bool available;
  final List<WhyYouMatchedReason> reasons;
  final int? overallScore;
  final String? insufficientReason;

  static const empty = WhyYouMatchedResult(
    available: false,
    reasons: [],
    insufficientReason: 'not_enough_data',
  );

  bool get hasReasons => reasons.isNotEmpty;

  factory WhyYouMatchedResult.fromReasons(
    List<WhyYouMatchedReason> reasons, {
    int? overallScore,
  }) {
    if (reasons.isEmpty) {
      return WhyYouMatchedResult(
        available: false,
        reasons: const [],
        overallScore: overallScore,
        insufficientReason: 'not_enough_data',
      );
    }
    return WhyYouMatchedResult(
      available: true,
      reasons: List.unmodifiable(reasons),
      overallScore: overallScore,
    );
  }
}
