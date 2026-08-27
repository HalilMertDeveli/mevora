import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Optional "How Humor Lab works" bottom sheet.
class HumorInfoSheet extends StatelessWidget {
  const HumorInfoSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const HumorInfoSheet(),
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.humorInfoTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              _Step(
                number: '1',
                title: l10n.humorInfoStep1Title,
                body: l10n.humorInfoStep1Body,
              ),
              _Step(
                number: '2',
                title: l10n.humorInfoStep2Title,
                body: l10n.humorInfoStep2Body,
              ),
              _Step(
                number: '3',
                title: l10n.humorInfoStep3Title,
                body: l10n.humorInfoStep3Body,
              ),
              _Step(
                number: '4',
                title: l10n.humorInfoStep4Title,
                body: l10n.humorInfoStep4Body,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.humorPrivacyNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              MevoraButton(
                label: l10n.humorAdContinue,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(number, style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
