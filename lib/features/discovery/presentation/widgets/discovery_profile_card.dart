import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_shadows.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_discover_badge.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_category_bar.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class DiscoveryProfileCard extends StatelessWidget {
  const DiscoveryProfileCard({
    super.key,
    required this.candidate,
    this.onTap,
    this.onWhyTap,
  });

  final DiscoveryCandidate candidate;
  final VoidCallback? onTap;
  final VoidCallback? onWhyTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final photo = candidate.photoUrl;
    final distance = candidate.distanceKm != null
        ? L10nFormat.distance(l10n, candidate.distanceKm!)
        : candidate.distanceLabel;
    final categoryBars = discoveryCategoryBars(context, candidate);
    final showScore = candidate.compatibilityStatus ==
            CompatibilityDisplayStatus.calculating ||
        candidate.compatibilityStatus == CompatibilityDisplayStatus.unavailable ||
        candidate.hasCompatibilityScore;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            color: theme.colorScheme.surfaceContainerLowest,
            boxShadow: AppShadows.discoveryCard(theme.brightness),
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
                      if (photo == null)
                        Center(
                          child: Icon(
                            Icons.person_outline,
                            size: 72,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        )
                      else
                        DiscoveryNetworkImage(url: photo),
                      if (candidate.isBoosted)
                        const Positioned(
                          top: AppSpacing.md,
                          left: AppSpacing.md,
                          child: DiscoveryBoostBadge(),
                        ),
                      if (candidate.isVerified)
                        const Positioned(
                          top: AppSpacing.md,
                          right: AppSpacing.md,
                          child: VerifiedProfileBadge(compact: true),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${candidate.displayName}, ${candidate.age}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (candidate.city != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          candidate.city!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (candidate.bio != null && candidate.bio!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          candidate.bio!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (showScore) ...[
                        const SizedBox(height: AppSpacing.md),
                        DiscoveryCompatibilityScore(
                          score: candidate.compatibilityScore,
                          status: candidate.compatibilityStatus,
                          onWhyTap: candidate.hasCompatibilityScore
                              ? onWhyTap
                              : null,
                        ),
                      ],
                      if (categoryBars.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        ...categoryBars,
                      ],
                      if (distance != null && distance.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        MevoraChip(label: distance, compact: true),
                      ],
                      if (candidate.sharedInterests.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.sharedHobbiesCount(
                            candidate.sharedInterests.length,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (candidate.interests.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: candidate.interests
                              .take(3)
                              .map(
                                (interest) => MevoraChip(
                                  label: interest,
                                  compact: true,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (candidate.compatibilityReasons.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          candidate.compatibilityReasons.first,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
