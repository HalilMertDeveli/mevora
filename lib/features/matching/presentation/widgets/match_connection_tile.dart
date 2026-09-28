import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// One conversation in the Matches inbox.
///
/// Reads like a messaging list — portrait, name, the last line, the time —
/// with compatibility as a small ring at the edge rather than a headline.
/// New connections are marked in ember; unread counts replace the ring.
class MatchConnectionTile extends StatelessWidget {
  const MatchConnectionTile({
    super.key,
    required this.item,
    required this.currentUid,
    this.breakdown,
    this.showOnlineIndicator = false,
    this.onTap,
    this.onWhyTap,
  });

  final MatchListItem item;
  final String currentUid;
  final CompatibilityBreakdown? breakdown;
  final bool showOnlineIndicator;
  final VoidCallback? onTap;
  final VoidCallback? onWhyTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    final unread = item.unreadCount(currentUid);
    final isNew = item.showNewMatchBadge;
    final isRelationship = item.match.isRelationshipTest;
    final lastMessage = item.match.lastMessage;
    final subtitle = isNew
        ? l10n.connectionBadgeNew
        : (lastMessage != null && lastMessage.isNotEmpty)
        ? lastMessage
        : l10n.connectionBadgeActive;

    Widget? trailing;
    if (unread > 0) {
      trailing = MevoraCountBadge(count: unread);
    } else if (breakdown != null) {
      trailing = CompatibilityRing(
        score: breakdown!.overallScore,
        size: 36,
        animate: false,
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          children: [
            MevoraAvatar(
              name: item.name,
              image: MevoraNetworkImages.provider(item.photoUrl),
              size: 56,
              isVerified: item.isVerified,
              showOnlineIndicator: showOnlineIndicator,
            ),
            const SizedBox(width: AppSpacing.s12 + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 16,
                            fontWeight: unread > 0 || isNew
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        L10nFormat.compactDate(l10n, item.match.occurredAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: unread > 0
                              ? theme.colorScheme.primary
                              : p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      if (isNew) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                      ],
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: isNew
                                ? theme.colorScheme.primary
                                : unread > 0
                                ? p.textPrimary
                                : p.textSecondary,
                            fontWeight: isNew || unread > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (breakdown != null && onWhyTap != null)
                    TextButton(
                      onPressed: onWhyTap,
                      style: TextButton.styleFrom(
                        foregroundColor: p.compatibility,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 36),
                        alignment: Alignment.centerLeft,
                        textStyle: theme.textTheme.labelMedium,
                      ),
                      child: Text(l10n.whyYouMatch),
                    ),
                  if (isRelationship) ...[
                    const SizedBox(height: AppSpacing.xs + 2),
                    MevoraPill(
                      label: l10n.relationshipMatchBadge,
                      tone: MevoraTone.compatibility,
                      dense: true,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
