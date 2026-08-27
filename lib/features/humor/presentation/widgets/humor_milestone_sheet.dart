import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

enum HumorMilestoneAction { continueFeed, openProfile }

/// Sparse milestone sheet (shaping / profile ready) — not every rating.
class HumorMilestoneSheet extends StatelessWidget {
  const HumorMilestoneSheet({
    super.key,
    required this.title,
    required this.body,
    this.showViewProfile = false,
  });

  final String title;
  final String body;
  final bool showViewProfile;

  static Future<HumorMilestoneAction?> show(
    BuildContext context, {
    required String title,
    required String body,
    bool showViewProfile = false,
  }) {
    return showModalBottomSheet<HumorMilestoneAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HumorMilestoneSheet(
        title: title,
        body: body,
        showViewProfile: showViewProfile,
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (showViewProfile) ...[
              MevoraButton(
                label: l10n.humorMilestoneViewProfile,
                onPressed: () =>
                    Navigator.of(context).pop(HumorMilestoneAction.openProfile),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(HumorMilestoneAction.continueFeed),
              child: Text(l10n.humorMilestoneContinue),
            ),
          ],
        ),
      ),
    );
  }
}
