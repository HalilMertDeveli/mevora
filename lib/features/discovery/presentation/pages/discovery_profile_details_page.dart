import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class DiscoveryProfileDetailsPage extends StatefulWidget {
  const DiscoveryProfileDetailsPage({super.key, required this.candidate});

  final DiscoveryCandidate candidate;

  @override
  State<DiscoveryProfileDetailsPage> createState() =>
      _DiscoveryProfileDetailsPageState();
}

class _DiscoveryProfileDetailsPageState
    extends State<DiscoveryProfileDetailsPage> {
  late final PageController _pageController = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final photos = candidate.photos;
    final distance = candidate.distanceKm != null
        ? L10nFormat.distance(l10n, candidate.distanceKm!)
        : candidate.distanceLabel;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileDetailsTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photos.isEmpty)
                      ColoredBox(
                        color: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.person_outline,
                          size: 72,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      )
                    else
                      PageView.builder(
                        controller: _pageController,
                        itemCount: photos.length,
                        onPageChanged: (index) =>
                            setState(() => _photoIndex = index),
                        itemBuilder: (context, index) {
                          return DiscoveryNetworkImage(url: photos[index]);
                        },
                      ),
                    if (photos.length > 1)
                      Positioned(
                        top: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(
                              alpha: 0.82,
                            ),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              l10n.photoCounter(_photoIndex + 1, photos.length),
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${candidate.displayName}, ${candidate.age}',
              style: theme.textTheme.headlineSmall,
            ),
            if (candidate.city != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                candidate.city!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (distance != null && distance.isNotEmpty)
                  MevoraChip(label: distance, compact: true),
                MevoraChip(
                  label: l10n.compatibilityPercent(candidate.compatibilityScore),
                  selected: true,
                  compact: true,
                ),
                if (candidate.relationshipGoal != null)
                  MevoraChip(
                    label: _relationshipLabel(l10n, candidate.relationshipGoal!),
                    compact: true,
                  ),
              ],
            ),
            if (candidate.bio != null && candidate.bio!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(l10n.bio, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(candidate.bio!, style: theme.textTheme.bodyLarge),
            ],
            if (candidate.interests.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(l10n.interests, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: candidate.interests
                    .map((interest) => MevoraChip(label: interest))
                    .toList(),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.whyYoureSeeingThis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            MevoraChip(
              label: l10n.compatibilityPercent(candidate.compatibilityScore),
              selected: true,
            ),
            if (candidate.sharedInterests.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.sharedInterests, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: candidate.sharedInterests
                    .map((interest) => MevoraChip(label: interest, compact: true))
                    .toList(),
              ),
            ],
            if (candidate.compatibilityReasons.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ...candidate.compatibilityReasons.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(reason, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _relationshipLabel(AppLocalizations l10n, String goal) {
    return switch (goal) {
      'longTerm' => l10n.relationshipGoalLongTerm,
      'casual' => l10n.relationshipGoalCasual,
      'figuringOut' => l10n.relationshipGoalFiguringOut,
      _ => goal,
    };
  }
}
