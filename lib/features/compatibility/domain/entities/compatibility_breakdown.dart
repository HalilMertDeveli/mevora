import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';

enum CompatibilityDataQuality {
  /// Enough signals for a meaningful overall score.
  sufficient,

  /// Some categories missing; overall is still computed from available data.
  partial,

  /// Too little data — do not show inflated scores.
  insufficient,
}

/// Multi-signal compatibility between viewer and candidate.
class CompatibilityBreakdown {
  const CompatibilityBreakdown({
    required this.overallScore,
    required this.relationshipScore,
    required this.interestScore,
    required this.lifestyleScore,
    this.questionScore,
    this.musicScore,
    this.communicationScore,
    this.proximityScore,
    this.activityScore,
    this.languageScore,
    this.hobbyScore,
    this.valuesScore,
    this.dataQuality = CompatibilityDataQuality.sufficient,
    this.reasons = const [],
    this.sharedInterests = const [],
    this.questionAlignedCount,
    this.questionSharedCount,
    this.strongestCategory,
    this.weakestCategory,
  });

  /// 0–100 inclusive.
  final int overallScore;
  final int relationshipScore;
  final int interestScore;
  final int lifestyleScore;
  final int? questionScore;
  final int? musicScore;
  final int? communicationScore;
  final int? proximityScore;
  final int? activityScore;
  final int? languageScore;
  final int? hobbyScore;
  final int? valuesScore;
  final CompatibilityDataQuality dataQuality;
  final List<CompatibilityReason> reasons;
  final List<String> sharedInterests;
  final int? questionAlignedCount;
  final int? questionSharedCount;
  final CompatibilityCategory? strongestCategory;
  final CompatibilityCategory? weakestCategory;

  bool get hasQuestionData =>
      questionScore != null &&
      questionSharedCount != null &&
      questionSharedCount! > 0;

  bool get hasMusicData => musicScore != null;

  CompatibilityBreakdown copyWith({
    int? overallScore,
    int? relationshipScore,
    int? interestScore,
    int? lifestyleScore,
    int? questionScore,
    int? musicScore,
    int? communicationScore,
    int? proximityScore,
    int? activityScore,
    int? languageScore,
    int? hobbyScore,
    int? valuesScore,
    CompatibilityDataQuality? dataQuality,
    List<CompatibilityReason>? reasons,
    List<String>? sharedInterests,
    int? questionAlignedCount,
    int? questionSharedCount,
    CompatibilityCategory? strongestCategory,
    CompatibilityCategory? weakestCategory,
  }) {
    return CompatibilityBreakdown(
      overallScore: overallScore ?? this.overallScore,
      relationshipScore: relationshipScore ?? this.relationshipScore,
      interestScore: interestScore ?? this.interestScore,
      lifestyleScore: lifestyleScore ?? this.lifestyleScore,
      questionScore: questionScore ?? this.questionScore,
      musicScore: musicScore ?? this.musicScore,
      communicationScore: communicationScore ?? this.communicationScore,
      proximityScore: proximityScore ?? this.proximityScore,
      activityScore: activityScore ?? this.activityScore,
      languageScore: languageScore ?? this.languageScore,
      hobbyScore: hobbyScore ?? this.hobbyScore,
      valuesScore: valuesScore ?? this.valuesScore,
      dataQuality: dataQuality ?? this.dataQuality,
      reasons: reasons ?? this.reasons,
      sharedInterests: sharedInterests ?? this.sharedInterests,
      questionAlignedCount: questionAlignedCount ?? this.questionAlignedCount,
      questionSharedCount: questionSharedCount ?? this.questionSharedCount,
      strongestCategory: strongestCategory ?? this.strongestCategory,
      weakestCategory: weakestCategory ?? this.weakestCategory,
    );
  }
}
