import 'package:flutter/material.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/presentation/compatibility_l10n.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// The scored signals in a real [CompatibilityBreakdown], strongest first.
List<CompatibilitySignal> compatibilitySignalsFromBreakdown(
  CompatibilityBreakdown breakdown, {
  int? limit,
}) {
  return rankSignals({
    CompatibilitySignalKind.relationship: breakdown.relationshipScore,
    CompatibilitySignalKind.lifestyle: breakdown.lifestyleScore,
    CompatibilitySignalKind.music: breakdown.musicScore,
    CompatibilitySignalKind.questions: breakdown.questionScore,
    CompatibilitySignalKind.interests: breakdown.interestScore,
    CompatibilitySignalKind.communication: breakdown.communicationScore,
    CompatibilitySignalKind.languages: breakdown.languageScore,
    CompatibilitySignalKind.hobbies: breakdown.hobbyScore,
    CompatibilitySignalKind.personalValues: breakdown.valuesScore,
  }, limit: limit);
}

/// Signal meters built from a real [CompatibilityBreakdown].
List<Widget> compatibilityCategoryBarsFromBreakdown(
  BuildContext context,
  CompatibilityBreakdown breakdown, {
  int maxBars = 4,
}) {
  return [
    for (final signal in compatibilitySignalsFromBreakdown(
      breakdown,
      limit: maxBars,
    ))
      CompatibilitySignalBar(signal: signal),
  ];
}

String? compatibilityStrongestLabel(
  AppLocalizations l10n,
  CompatibilityBreakdown breakdown,
) {
  final category = breakdown.strongestCategory;
  if (category == null) {
    return null;
  }
  return CompatibilityL10n.category(l10n, category);
}
