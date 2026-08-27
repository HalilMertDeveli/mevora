import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

/// Optional match humor sheet (MVP: unused in match UI).
class HumorCompatibilitySheet extends StatelessWidget {
  const HumorCompatibilitySheet({
    super.key,
    required this.score,
    this.strongestShared = const [],
  });

  final int score;
  final List<String> strongestShared;

  static Future<void> show(
    BuildContext context, {
    required int score,
    List<String> strongestShared = const [],
  }) {
    final analytics = BoostScope.maybeOf(context)?.analytics;
    if (analytics != null) {
      unawaited(analytics.logEvent(AnalyticsEvents.humorCompatibilityViewed));
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HumorCompatibilitySheet(
        score: score,
        strongestShared: strongestShared,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.humorCompatibilityTitle,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$score%',
              style: theme.textTheme.displaySmall,
            ),
            if (strongestShared.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(l10n.humorTopVibes, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final vibe in strongestShared)
                    MevoraChip(label: vibe, selected: true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
