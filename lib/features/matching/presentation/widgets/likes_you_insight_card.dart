import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_category_bars.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

/// Insight-led liker card — compatibility when real data exists.
class LikesYouInsightCard extends StatelessWidget {
  const LikesYouInsightCard({
    super.key,
    required this.item,
    required this.onTap,
    this.breakdown,
    this.onConnect,
  });

  final IncomingLikerPreview item;
  final VoidCallback onTap;
  final CompatibilityBreakdown? breakdown;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = [
      if (item.age != null && item.age! > 0) '${item.age}',
      if (item.city != null && item.city!.isNotEmpty) item.city!,
    ].join(' · ');
    final bars = breakdown == null
        ? const <Widget>[]
        : compatibilityCategoryBarsFromBreakdown(
            context,
            breakdown!,
            maxBars: 3,
          );

    return MevoraCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MevoraAvatar(
                  name: item.displayName,
                  image: MevoraNetworkImages.provider(item.photoUrl),
                  size: 52,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.insights_outlined,
                  color: AppColors.softGreen,
                  size: 22,
                ),
              ],
            ),
            if (breakdown != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.likesYouCompatibilityLabel(breakdown!.overallScore),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.softGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...bars,
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.likesYouInsightSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: MevoraButton(
                    label: l10n.likesYouSeeWhy,
                    variant: MevoraButtonVariant.secondary,
                    size: MevoraButtonSize.small,
                    onPressed: onTap,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MevoraButton(
                    label: l10n.discoveryActionConnect,
                    size: MevoraButtonSize.small,
                    onPressed: onConnect ?? onTap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry card on the Matches tab — insight-led, not heart-centric.
class LikesYouEntryCard extends StatelessWidget {
  const LikesYouEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: MevoraCard(
        onTap: onTap,
        child: ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.softGreen.withValues(alpha: 0.14),
              border: Border.all(
                color: AppColors.softGreen.withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.insights_outlined,
              color: AppColors.softGreen,
              size: 22,
            ),
          ),
          title: Text(l10n.likesYouTitle, style: theme.textTheme.titleMedium),
          subtitle: Text(l10n.likesYouEntrySubtitle),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
