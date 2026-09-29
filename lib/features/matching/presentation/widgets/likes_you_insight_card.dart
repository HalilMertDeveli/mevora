import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/presentation/compatibility_l10n.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_category_bars.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Someone who liked you — and, when Mevora has the data, why you two fit.
/// One action: open their profile, where connecting happens.
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
    final signals = breakdown == null
        ? const <CompatibilitySignal>[]
        : compatibilitySignalsFromBreakdown(breakdown!, limit: 3);

    return MevoraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MevoraAvatar(
                name: item.displayName,
                image: MevoraNetworkImages.provider(item.photoUrl),
                size: 56,
              ),
              const SizedBox(width: AppSpacing.s12 + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.displayName, style: theme.textTheme.titleMedium),
                    if (meta.isNotEmpty)
                      Text(meta, style: theme.textTheme.bodySmall),
                    if (breakdown != null)
                      Text(
                        CompatibilityL10n.tier(l10n, breakdown!.overallScore),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.palette.compatibility,
                        ),
                      ),
                  ],
                ),
              ),
              if (breakdown != null)
                CompatibilityRing(score: breakdown!.overallScore, size: 44),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          if (signals.isNotEmpty)
            CompatibilitySignalPills(signals: signals, showScores: false)
          else
            Text(
              l10n.likesYouInsightSubtitle,
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: AppSpacing.md),
          MevoraButton(
            label: l10n.likesYouSeeWhy,
            icon: MevoraIcons.compatibility,
            variant: MevoraButtonVariant.tonal,
            size: MevoraButtonSize.small,
            onPressed: onConnect ?? onTap,
          ),
        ],
      ),
    );
  }
}

/// Entry point on the Matches tab: "People who liked you".
class LikesYouEntryCard extends StatelessWidget {
  const LikesYouEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        AppSpacing.xs,
      ),
      child: MevoraCard(
        onTap: onTap,
        color: p.matchContainer,
        padding: const EdgeInsets.all(AppSpacing.md),
        semanticLabel: l10n.likesYouTitle,
        child: Row(
          children: [
            MevoraIconBadge(
              icon: MevoraIcons.liked,
              tone: MevoraTone.match,
              size: 44,
              circle: true,
              background: p.surface,
            ),
            const SizedBox(width: AppSpacing.s12 + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.likesYouTitle, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.likesYouEntrySubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(MevoraIcons.chevronRight, size: 18, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}
