import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_badge.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_compatibility_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class DiscoveryProfileCard extends StatelessWidget {
  const DiscoveryProfileCard({super.key, required this.candidate, this.onTap});

  final DiscoveryCandidate candidate;
  final VoidCallback? onTap;

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
                const ColoredBox(color: AppColors.nightSurface),
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
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x33140F16),
                        Color(0x00140F16),
                        Color(0xCC140F16),
                        Color(0xF2140F16),
                      ],
                      stops: [0, 0.38, 0.72, 1],
                    ),
                  ),
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
                          color: const Color(0xFFF4EEE8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (candidate.city != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          candidate.city!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFD8D0DA),
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
                            color: const Color(0xFFD8D0DA),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          MevoraChip(
                            label: l10n.compatibilityPercent(
                              candidate.compatibilityScore,
                            ),
                            selected: true,
                            compact: true,
                          ),
                          if (candidate.musicCompatibilityScore != null)
                            MusicCompatibilityBadge(
                              score: candidate.musicCompatibilityScore!,
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
                            color: const Color(0xFFF4EEE8),
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
                            color: const Color(0xFFD8D0DA),
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
