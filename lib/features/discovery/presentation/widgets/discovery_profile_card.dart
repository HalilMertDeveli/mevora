import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_decorations.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_discover_badge.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_badge.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_compatibility_badge.dart';
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.card),
                if (photo == null)
                  Center(
                    child: Icon(
                      Icons.person_outline,
                      size: 88,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  )
                else
                  DiscoveryNetworkImage(url: photo),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppDecorations.photoOverlayGradient(),
                  ),
                ),
                if (candidate.isBoosted)
                  const Positioned(
                    top: AppSpacing.md,
                    left: AppSpacing.md,
                    child: DiscoveryBoostBadge(),
                  ),
                Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${candidate.displayName}, ${candidate.age}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (candidate.isVerified) ...[
                        const SizedBox(height: AppSpacing.xs),
                        const VerifiedProfileBadge(compact: true),
                      ],
                      if (candidate.city != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          candidate.city!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                      if (candidate.bio != null &&
                          candidate.bio!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          candidate.bio!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (candidate.compatibilityStatus ==
                                  CompatibilityDisplayStatus.calculating ||
                              candidate.compatibilityStatus ==
                                  CompatibilityDisplayStatus.unavailable ||
                              candidate.hasCompatibilityScore)
                            CompatibilityDiscoverBadge(
                              score: candidate.compatibilityScore,
                              status: candidate.compatibilityStatus,
                              onTap: candidate.hasCompatibilityScore
                                  ? onWhyTap
                                  : null,
                            ),
                          if (candidate.musicCompatibilityScore != null)
                            MusicCompatibilityBadge(
                              score: candidate.musicCompatibilityScore!,
                              sharedTracks: candidate.sharedMusicTracks,
                              sharedArtists: candidate.sharedMusicArtists,
                              sharedGenres: candidate.sharedMusicGenres,
                              insights: candidate.musicInsights,
                              sharedTrackCount: candidate.sharedMusicTrackCount,
                              sharedArtistCount:
                                  candidate.sharedMusicArtistCount,
                              sharedPlaylistTrackCount:
                                  candidate.sharedMusicPlaylistTrackCount,
                            ),
                          if (candidate.relationshipCompatibilityScore != null)
                            RelationshipCompatibilityBadge(
                              score: candidate.relationshipCompatibilityScore!,
                            ),
                          if (distance != null && distance.isNotEmpty)
                            MevoraChip(label: distance, compact: true),
                          if (candidate.isDemo)
                            MevoraChip(
                              label: l10n.demoProfileBadge,
                              compact: true,
                            ),
                        ],
                      ),
                      if (candidate.sharedInterests.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.sharedHobbiesCount(
                            candidate.sharedInterests.length,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.primaryText,
                          ),
                        ),
                      ],
                      if (candidate.interests.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: candidate.interests
                              .take(3)
                              .map(
                                (interest) =>
                                    MevoraChip(label: interest, compact: true),
                              )
                              .toList(),
                        ),
                      ],
                      if (candidate.compatibilityReasons.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '✓ ${candidate.compatibilityReasons.first}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondaryText,
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
