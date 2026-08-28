import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_category.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_evidence.dart';

/// Validation failure when constructing a structured match reason.
enum WhyYouMatchedReasonValidationError {
  emptyId,
  emptyTitle,
  emptyDescription,
  invalidScore,
  missingEvidence,
  invalidConfidence,
}

/// Result of attempting to create a [WhyYouMatchedReason].
class WhyYouMatchedReasonCreateResult {
  const WhyYouMatchedReasonCreateResult._({this.reason, this.error});

  const WhyYouMatchedReasonCreateResult.ok(WhyYouMatchedReason reason)
      : this._(reason: reason);

  const WhyYouMatchedReasonCreateResult.fail(
    WhyYouMatchedReasonValidationError error,
  ) : this._(error: error);

  final WhyYouMatchedReason? reason;
  final WhyYouMatchedReasonValidationError? error;

  bool get isValid => reason != null && error == null;
}

/// Structured “Neden Eşleştiniz?” reason.
///
/// Separate from legacy [CompatibilityReason] (messageKey-only bullets).
/// Every instance must carry real [evidence] — never fabricate claims.
class WhyYouMatchedReason {
  const WhyYouMatchedReason._({
    required this.id,
    required this.category,
    required this.score,
    required this.strength,
    required this.title,
    required this.description,
    required this.evidence,
    required this.confidence,
    required this.priority,
    this.titleArgs = const [],
    this.descriptionArgs = const [],
    this.iconName,
  });

  final String id;
  final WhyYouMatchedCategory category;

  /// Category signal 0–100 from real comparison.
  final int score;
  final WhyYouMatchedStrength strength;

  /// Localization key (or short stable key) for the headline.
  final String title;

  /// Localization key for the evidence line.
  final String description;
  final List<String> titleArgs;
  final List<String> descriptionArgs;
  final WhyYouMatchedEvidence evidence;

  /// Data quality / sample-size confidence in \[0.0, 1.0\].
  final double confidence;

  /// Higher values surface first after priority sorting.
  final int priority;
  final String? iconName;

  String get resolvedIconName => iconName ?? category.defaultIconName;

  /// Creates a reason only when all validation rules pass.
  static WhyYouMatchedReasonCreateResult create({
    required String id,
    required WhyYouMatchedCategory category,
    required int score,
    required String title,
    required String description,
    required WhyYouMatchedEvidence evidence,
    required double confidence,
    int? priority,
    WhyYouMatchedStrength? strength,
    List<String> titleArgs = const [],
    List<String> descriptionArgs = const [],
    String? iconName,
  }) {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) {
      return const WhyYouMatchedReasonCreateResult.fail(
        WhyYouMatchedReasonValidationError.emptyId,
      );
    }
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return const WhyYouMatchedReasonCreateResult.fail(
        WhyYouMatchedReasonValidationError.emptyTitle,
      );
    }
    final trimmedDescription = description.trim();
    if (trimmedDescription.isEmpty) {
      return const WhyYouMatchedReasonCreateResult.fail(
        WhyYouMatchedReasonValidationError.emptyDescription,
      );
    }
    if (score < 0 || score > 100) {
      return const WhyYouMatchedReasonCreateResult.fail(
        WhyYouMatchedReasonValidationError.invalidScore,
      );
    }
    if (!evidence.isValid) {
      return const WhyYouMatchedReasonCreateResult.fail(
        WhyYouMatchedReasonValidationError.missingEvidence,
      );
    }
    if (confidence < 0.0 || confidence > 1.0 || confidence.isNaN) {
      return const WhyYouMatchedReasonCreateResult.fail(
        WhyYouMatchedReasonValidationError.invalidConfidence,
      );
    }

    final resolvedStrength =
        strength ?? WhyYouMatchedStrengthX.fromScore(score);
    final resolvedPriority = priority ?? (score * confidence).round();

    return WhyYouMatchedReasonCreateResult.ok(
      WhyYouMatchedReason._(
        id: trimmedId,
        category: category,
        score: score,
        strength: resolvedStrength,
        title: trimmedTitle,
        description: trimmedDescription,
        titleArgs: titleArgs,
        descriptionArgs: descriptionArgs,
        evidence: evidence,
        confidence: confidence,
        priority: resolvedPriority,
        iconName: iconName,
      ),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'category': category.wireValue,
        'score': score,
        'strength': strength.name,
        'title': title,
        'description': description,
        'titleArgs': titleArgs,
        'descriptionArgs': descriptionArgs,
        'evidence': evidence.toJson(),
        'confidence': confidence,
        'priority': priority,
        'iconName': resolvedIconName,
      };
}
