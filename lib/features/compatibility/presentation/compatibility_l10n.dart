import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Human-readable overall compatibility, strongest first. The tier is the
/// message and the percentage is detail — see docs/product-language.md.
enum CompatibilityTier { strong, close, notable, some }

/// Resolves deterministic compatibility reason keys to localized copy.
abstract final class CompatibilityL10n {
  /// A dimension must reach this before Mevora says it is what two people
  /// share most; below it the strongest dimension is still not a strength.
  static const int strongestFloor = 70;

  static CompatibilityTier tierOf(int score) {
    if (score >= 80) return CompatibilityTier.strong;
    if (score >= 65) return CompatibilityTier.close;
    if (score >= 50) return CompatibilityTier.notable;
    return CompatibilityTier.some;
  }

  static String tier(AppLocalizations l10n, int score) {
    return switch (tierOf(score)) {
      CompatibilityTier.strong => l10n.compatTierStrong,
      CompatibilityTier.close => l10n.compatTierClose,
      CompatibilityTier.notable => l10n.compatTierNotable,
      CompatibilityTier.some => l10n.compatTierSome,
    };
  }

  /// "Güçlü eşleşme · %87 uyum" — tier first, percentage as detail.
  static String tierWithPercent(AppLocalizations l10n, int score) =>
      '${tier(l10n, score)} · ${l10n.compatDiscoverBadge(score)}';

  /// What the strongest dimension means for the two people, or null when it
  /// is not strong enough to be called a strength honestly.
  static String? strongest(
    AppLocalizations l10n,
    CompatibilityBreakdown breakdown,
  ) {
    final top = breakdown.strongestCategory;
    if (top == null) {
      return null;
    }
    final score = _categoryScore(breakdown, top);
    if (score == null || score < strongestFloor) {
      return null;
    }
    return switch (top) {
      CompatibilityCategory.relationship => l10n.compatStrongestRelationship,
      CompatibilityCategory.lifeValues => l10n.compatStrongestValues,
      CompatibilityCategory.questions => l10n.compatStrongestQuestions,
      CompatibilityCategory.music => l10n.compatStrongestMusic,
      CompatibilityCategory.lifestyle => l10n.compatStrongestLifestyle,
      CompatibilityCategory.interests ||
      CompatibilityCategory.hobbies => l10n.compatStrongestInterests,
      CompatibilityCategory.communication => l10n.compatStrongestCommunication,
      CompatibilityCategory.languages => l10n.compatStrongestLanguages,
      CompatibilityCategory.overall ||
      CompatibilityCategory.proximity ||
      CompatibilityCategory.activity => l10n.matchStrongestConnectionLabel(
        category(l10n, top),
      ),
    };
  }

  static int? _categoryScore(
    CompatibilityBreakdown breakdown,
    CompatibilityCategory category,
  ) {
    return switch (category) {
      CompatibilityCategory.overall => breakdown.overallScore,
      CompatibilityCategory.relationship => breakdown.relationshipScore,
      CompatibilityCategory.interests => breakdown.interestScore,
      CompatibilityCategory.languages => breakdown.languageScore,
      CompatibilityCategory.hobbies => breakdown.hobbyScore,
      CompatibilityCategory.lifestyle => breakdown.lifestyleScore,
      CompatibilityCategory.lifeValues => breakdown.valuesScore,
      CompatibilityCategory.questions => breakdown.questionScore,
      CompatibilityCategory.music => breakdown.musicScore,
      CompatibilityCategory.communication => breakdown.communicationScore,
      CompatibilityCategory.proximity || CompatibilityCategory.activity => null,
    };
  }

  static String reason(AppLocalizations l10n, CompatibilityReason reason) {
    switch (reason.messageKey) {
      case 'compatReasonSameRelationshipGoal':
        return sameGoal(l10n, reason.messageArgs.firstOrNull) ??
            l10n.compatReasonSameRelationshipGoal;
      case 'compatReasonSharedInterests':
        return l10n.compatReasonSharedInterests(
          _labels(
            reason.messageArgs,
            (id) => OnboardingLabels.interest(l10n, id),
          ),
        );
      case 'compatReasonSharedLanguages':
        return l10n.compatReasonSharedLanguages(
          _labels(
            reason.messageArgs,
            (id) => OnboardingLabels.language(l10n, id),
          ),
        );
      case 'compatReasonSharedHobbies':
        return l10n.compatReasonSharedHobbies(
          _labels(reason.messageArgs, (id) => OnboardingLabels.hobby(l10n, id)),
        );
      case 'compatReasonSimilarLifestyle':
        return l10n.compatReasonSimilarLifestyle;
      case 'compatReasonSameAnswers':
        return l10n.compatReasonSameAnswers(
          reason.messageArgs.elementAt(0),
          reason.messageArgs.elementAt(1),
        );
      case 'compatReasonSimilarMusic':
        return l10n.compatReasonSimilarMusic;
      case 'compatReasonCommunication':
        return l10n.compatReasonCommunication;
      default:
        return reason.messageKey;
    }
  }

  /// "İkiniz de uzun süreli bir ilişki arıyorsunuz" for a goal both people
  /// share. Null for a goal that says nothing about what they want.
  static String? sameGoal(AppLocalizations l10n, String? rawGoal) {
    return switch (CompatibilityScoring.normalizeRelationshipGoal(rawGoal)) {
      OnboardingRelationshipGoal.longTerm => l10n.compatReasonGoalLongTerm,
      OnboardingRelationshipGoal.shortTerm => l10n.compatReasonGoalShortTerm,
      OnboardingRelationshipGoal.friendship => l10n.compatReasonGoalFriendship,
      OnboardingRelationshipGoal.notSure => l10n.compatReasonGoalNotSure,
      _ => null,
    };
  }

  /// Localizes the fixed reason codes the discovery backend sends in
  /// `compatibilityReasons`. Unknown codes return null and are not shown — a
  /// raw English server string must never reach a Turkish screen.
  static String? serverReason(
    AppLocalizations l10n,
    String code, {
    String? relationshipGoal,
  }) {
    return switch (code.trim().toLowerCase()) {
      'shared interests' => l10n.compatReasonSomeSharedInterests,
      'same relationship goal' => sameGoal(l10n, relationshipGoal),
      'similar relationship views' => l10n.compatReasonSimilarViews,
      'similar music taste' => l10n.compatReasonSimilarMusic,
      'similar lifestyle' => l10n.compatReasonSimilarLifestyle,
      _ => null,
    };
  }

  static List<String> serverReasons(
    AppLocalizations l10n,
    List<String> codes, {
    String? relationshipGoal,
  }) {
    return codes
        .map(
          (code) =>
              serverReason(l10n, code, relationshipGoal: relationshipGoal),
        )
        .whereType<String>()
        .toList();
  }

  static String category(
    AppLocalizations l10n,
    CompatibilityCategory category,
  ) {
    return switch (category) {
      CompatibilityCategory.overall => l10n.compatCategoryOverall,
      CompatibilityCategory.relationship => l10n.compatCategoryRelationship,
      CompatibilityCategory.interests => l10n.compatCategoryInterests,
      CompatibilityCategory.languages => l10n.compatCategoryLanguages,
      CompatibilityCategory.hobbies => l10n.compatCategoryHobbies,
      CompatibilityCategory.lifestyle => l10n.compatCategoryLifestyle,
      CompatibilityCategory.lifeValues => l10n.compatCategoryValues,
      CompatibilityCategory.questions => l10n.compatCategoryQuestions,
      CompatibilityCategory.music => l10n.compatCategoryMusic,
      CompatibilityCategory.communication => l10n.compatCategoryCommunication,
      CompatibilityCategory.proximity => l10n.compatCategoryProximity,
      CompatibilityCategory.activity => l10n.compatCategoryActivity,
    };
  }

  /// Localized labels for comma-separated ids, without the flag emoji the
  /// language picker labels carry.
  static String _labels(List<String> args, String Function(String id) label) {
    return args
        .expand((arg) => arg.split(','))
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .map((id) => label(id).replaceAll(_flag, '').trim())
        .join(', ');
  }

  static final RegExp _flag = RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true);
}
