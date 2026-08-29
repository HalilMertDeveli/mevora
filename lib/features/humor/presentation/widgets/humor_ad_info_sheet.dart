import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

enum HumorAdInfoResult { continueFeed, openPremium }

/// Shown once for free users before the first Humor Lab ad.
class HumorAdInfoSheet extends StatelessWidget {
  const HumorAdInfoSheet({super.key});

  static Future<HumorAdInfoResult?> show(BuildContext context) {
    return showModalBottomSheet<HumorAdInfoResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const HumorAdInfoSheet(),
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
            Text(
              l10n.humorAdInfoTitle,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.humorAdInfoBody,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.humorAdInfoPremiumHint,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            MevoraButton(
              label: l10n.humorAdContinue,
              onPressed: () =>
                  Navigator.of(context).pop(HumorAdInfoResult.continueFeed),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop(HumorAdInfoResult.openPremium);
                unawaited(context.push(AppRoutes.premium));
              },
              child: Text(l10n.humorAdInfoPremiumCta),
            ),
          ],
        ),
      ),
    );
  }
}
