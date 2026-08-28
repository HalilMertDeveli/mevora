import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/services/humor_education_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Compact premium upsell — never floats over feed media.
class HumorPremiumCard extends StatelessWidget {
  const HumorPremiumCard({
    super.key,
    required this.isPremium,
    this.compact = false,
  });

  final bool isPremium;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (isPremium) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: compact ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.humorPremiumActiveBadge,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  l10n.humorPremiumCardTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.humorPremiumCardBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push(AppRoutes.boost),
                child: Text(l10n.humorPremiumCardCta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared learning progress block used on intro + feed chrome.
class HumorProgressBlock extends StatelessWidget {
  const HumorProgressBlock({
    super.key,
    required this.interactionCount,
    this.showHint = false,
  });

  final int interactionCount;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = HumorEducationPolicy.learningProgress(interactionCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '🎭 ${l10n.humorProgressTitle}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.humorProgressCount(interactionCount),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
          ),
        ),
        if (showHint) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.humorProgressHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// First-open Humor Lab introduction — responsive, scrollable, no fixed columns.
class HumorIntroView extends StatelessWidget {
  const HumorIntroView({
    super.key,
    required this.onContinue,
    this.interactionCount = 0,
    this.isPremium = false,
    this.onOpenInfo,
  });

  final VoidCallback onContinue;
  final int interactionCount;
  final bool isPremium;
  final VoidCallback? onOpenInfo;

  static const double _contentMaxWidth = 520;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 700;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.humorLabTitle),
        actions: [
          IconButton(
            tooltip: l10n.humorInfoTooltip,
            onPressed: onOpenInfo,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: compact ? AppSpacing.md : AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '😂',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: compact ? 40 : 52,
                      ),
                    ),
                    SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                    Text(
                      l10n.humorIntroTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                    Text(
                      l10n.humorIntroBody1,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.humorIntroBody2,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.humorIntroBody3,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
                    const HumorWhyMattersSection(),
                    SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
                    MevoraButton(
                      label: l10n.humorIntroCta,
                      onPressed: onContinue,
                    ),
                    SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
                    HumorProgressBlock(
                      interactionCount: interactionCount,
                      showHint: true,
                    ),
                    SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                    HumorPremiumCard(
                      isPremium: isPremium,
                      compact: compact,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains why Humor Lab matters for Mevora — intro + profile surfaces.
class HumorWhyMattersSection extends StatelessWidget {
  const HumorWhyMattersSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '❤️ ${l10n.humorWhyMattersTitle}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.humorWhyMattersBody1,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.humorWhyMattersBody2,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
