import 'package:flutter/material.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_category_bar.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Builds category progress bars from a real [CompatibilityBreakdown].
List<Widget> compatibilityCategoryBarsFromBreakdown(
  BuildContext context,
  CompatibilityBreakdown breakdown, {
  int maxBars = 4,
}) {
  final l10n = AppLocalizations.of(context);
  final entries = <({String label, int score})>[];

  void add(String label, int? score) {
    if (score != null && score > 0) {
      entries.add((label: label, score: score));
    }
  }

  add(l10n.compatCategoryRelationship, breakdown.relationshipScore);
  add(l10n.compatCategoryLifestyle, breakdown.lifestyleScore);
  add(l10n.compatCategoryMusic, breakdown.musicScore);
  add(l10n.compatCategoryQuestions, breakdown.questionScore);
  add(l10n.compatCategoryInterests, breakdown.interestScore);
  add(l10n.compatCategoryCommunication, breakdown.communicationScore);
  add(l10n.compatCategoryLanguages, breakdown.languageScore);
  add(l10n.compatCategoryHobbies, breakdown.hobbyScore);
  add(l10n.compatCategoryValues, breakdown.valuesScore);

  entries.sort((a, b) => b.score.compareTo(a.score));
  return entries
      .take(maxBars)
      .map((e) => DiscoveryCategoryBar(label: e.label, score: e.score))
      .toList();
}
