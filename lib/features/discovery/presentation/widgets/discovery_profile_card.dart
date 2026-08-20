import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class DiscoveryProfileCard extends StatelessWidget {
  const DiscoveryProfileCard({
    super.key,
    required this.candidate,
    this.onTap,
  });

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
    return MevoraCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      emphasis: MevoraCardEmphasis.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.lg),
              ),
              child: photo == null
                  ? ColoredBox(
                      color: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.person_outline,
                        size: 72,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    )
                  : DiscoveryNetworkImage(url: photo),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${candidate.displayName}, ${candidate.age}',
                      style: theme.textTheme.titleLarge,
                    ),
                    if (candidate.city != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        candidate.city!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (distance != null && distance.isNotEmpty)
                          MevoraChip(label: distance, compact: true),
                        MevoraChip(
                          label: l10n.compatibilityPercent(
                            candidate.compatibilityScore,
                          ),
                          selected: true,
                          compact: true,
                        ),
                      ],
                    ),
                    if (candidate.bio != null && candidate.bio!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        candidate.bio!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (candidate.interests.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: candidate.interests
                            .take(5)
                            .map(
                              (interest) =>
                                  MevoraChip(label: interest, compact: true),
                            )
                            .toList(),
                      ),
                    ],
                    if (candidate.compatibilityReasons.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.compatibilityReasonsHeading,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ...candidate.compatibilityReasons.take(2).map(
                        (reason) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(
                            '• $reason',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
