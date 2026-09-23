import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_category_bars.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

/// Connection-first match row with optional real compatibility breakdown.
class MatchConnectionTile extends StatelessWidget {
  const MatchConnectionTile({
    super.key,
    required this.item,
    required this.currentUid,
    this.breakdown,
    this.showOnlineIndicator = false,
    this.isReadOnlyHistory = false,
    this.onTap,
    this.onWhyTap,
  });

  final MatchListItem item;
  final String currentUid;
  final CompatibilityBreakdown? breakdown;
  final bool showOnlineIndicator;

  /// Retained conversation with a deleted account: no photo, no presence, no
  /// compatibility, and a localized "Deleted account" label instead of whatever
  /// name the match document still carries.
  final bool isReadOnlyHistory;
  final VoidCallback? onTap;
  final VoidCallback? onWhyTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unread = item.unreadCount(currentUid);
    final isNew = isReadOnlyHistory ? false : item.showNewMatchBadge;
    final photo = isReadOnlyHistory ? null : item.photoUrl;
    final displayName = isReadOnlyHistory ? l10n.deletedAccountName : item.name;
    final isRelationship = item.match.isRelationshipTest;
    final bars = (breakdown == null || isReadOnlyHistory)
        ? const <Widget>[]
        : compatibilityCategoryBarsFromBreakdown(
            context,
            breakdown!,
            maxBars: 2,
          );

    final subtitle = isReadOnlyHistory
        ? l10n.settingsReadOnly
        : [
            if (isRelationship) l10n.relationshipMatchBadge,
            if (isNew)
              l10n.connectionBadgeNew
            else if (item.match.lastMessage != null)
              item.match.lastMessage!
            else
              l10n.connectionBadgeActive,
          ].where((part) => part.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: MevoraCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MevoraAvatar(
                name: displayName,
                image: MevoraNetworkImages.provider(photo),
                size: 56,
                isVerified: isReadOnlyHistory ? false : item.isVerified,
                showOnlineIndicator:
                    isReadOnlyHistory ? false : showOnlineIndicator,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          L10nFormat.compactDate(
                            l10n,
                            item.match.occurredAt,
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (breakdown != null && !isReadOnlyHistory) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${breakdown!.overallScore}%',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: AppColors.softGreen,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                      Text(
                        l10n.compatScoreHeading,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (bars.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        ...bars,
                      ],
                      if (onWhyTap != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        InkWell(
                          onTap: onWhyTap,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.whyYouMatch,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: theme.colorScheme.secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ] else if (isRelationship) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.relationshipTestAlign,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.softGreen,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (unread > 0)
                CircleAvatar(
                  radius: 10,
                  child: Text('$unread', style: theme.textTheme.labelSmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
