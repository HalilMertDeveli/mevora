import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

/// Match humor details: the coarse reading, the styles both people share and
/// a plain note that this is a light signal, not a verdict. No numbers.
///
/// `humor_compatibility_viewed` is logged by the chat banner once per open,
/// not here, so opening the sheet does not double-count it.
class HumorCompatibilitySheet extends StatelessWidget {
  const HumorCompatibilitySheet({
    super.key,
    required this.score,
    this.strongestShared = const [],
  });

  /// 0–100 from the server; only used to pick the bucket.
  final int score;
  final List<HumorCategory> strongestShared;

  /// "Your humor match is high / moderate / low" for [level].
  static String levelLabel(
    AppLocalizations l10n,
    HumorCompatibilityLevel level,
  ) {
    return switch (level) {
      HumorCompatibilityLevel.high => l10n.humorCompatibilityLevelHigh,
      HumorCompatibilityLevel.medium => l10n.humorCompatibilityLevelMedium,
      HumorCompatibilityLevel.low => l10n.humorCompatibilityLevelLow,
    };
  }

  static Future<void> show(
    BuildContext context, {
    required int score,
    List<HumorCategory> strongestShared = const [],
  }) {
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
    final level = HumorCompatibility.levelOf(score);

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
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(levelLabel(l10n, level), style: theme.textTheme.headlineSmall),
            if (strongestShared.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.humorCompatibilitySharedStyles,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final category in strongestShared)
                    MevoraChip(
                      label: HumorProfileDisplay.categoryLabel(l10n, category),
                      selected: true,
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.humorCompatibilityNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
