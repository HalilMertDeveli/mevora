import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_shadows.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/copy/pick_copy.dart';
import 'package:mevora/features/picks/presentation/widgets/pick_type_badge.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// One Mevora Pick: who, and why Mevora chose them — then the decision.
class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.pick,
    required this.onOpen,
    required this.onLike,
    required this.onPass,
    this.busy = false,
  });

  final MevoraPick pick;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onPass;

  /// A decision for this Pick is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final candidate = pick.candidate;
    final supporting = PickCopy.supportingLine(l10n, pick);
    final distance = candidate.distanceKm != null
        ? L10nFormat.distance(l10n, candidate.distanceKm!)
        : candidate.distanceLabel;
    final place = [
      if (candidate.city != null && candidate.city!.isNotEmpty) candidate.city!,
      if (distance != null && distance.isNotEmpty) distance,
    ].join(' · ');
    final nameLine = candidate.age > 0
        ? '${candidate.displayName}, ${candidate.age}'
        : candidate.displayName;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        color: theme.colorScheme.surfaceContainerLowest,
        boxShadow: AppShadows.discoveryCard(theme.brightness),
        border: Border.all(color: context.palette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: l10n.picksOpenProfileSemantics(candidate.displayName),
              child: InkWell(
                onTap: onOpen,
                child: AspectRatio(
                  aspectRatio: 4 / 4.2,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
                      if (candidate.photoUrl == null)
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
                        DiscoveryNetworkImage(url: candidate.photoUrl!),
                      const _BottomScrim(),
                      Positioned(
                        top: AppSpacing.md,
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: PickTypeBadge(
                                  type: pick.pickType,
                                  onMedia: true,
                                ),
                              ),
                            ),
                            if (candidate.isVerified) ...[
                              const SizedBox(width: AppSpacing.sm),
                              const VerifiedProfileBadge(compact: true),
                            ],
                          ],
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
                            if (candidate.isBoosted) ...[
                              const DiscoveryBoostBadge(),
                              const SizedBox(height: AppSpacing.xs),
                            ],
                            Text(
                              nameLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (place.isNotEmpty)
                              Text(
                                place,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PickCopy.headline(l10n, pick),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (supporting != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      supporting,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (candidate.compatibilityScore > 0)
                        _ScorePill(score: candidate.compatibilityScore),
                      for (final label in pick.secondaryLabels.take(2))
                        PickTypeBadge(type: label, emphasized: false),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: PickDecisionBar(
                name: candidate.displayName,
                busy: busy,
                onLike: onLike,
                onPass: onPass,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pass / Like, shared by the card and the profile page.
class PickDecisionBar extends StatelessWidget {
  const PickDecisionBar({
    super.key,
    required this.name,
    required this.onLike,
    required this.onPass,
    this.busy = false,
  });

  final String name;
  final VoidCallback onLike;
  final VoidCallback onPass;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: l10n.picksPassSemantics(name),
            excludeSemantics: true,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onPass,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.close_rounded),
              label: Text(l10n.picksPass, maxLines: 1),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Semantics(
            button: true,
            label: l10n.picksLikeSemantics(name),
            excludeSemantics: true,
            child: FilledButton.icon(
              onPressed: busy ? null : onLike,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.favorite_rounded),
              label: Text(l10n.picksLike, maxLines: 1),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          l10n.picksMatchScore(score),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.25, 0.6, 1.0],
          colors: [
            Color(0x55000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0xB3000000),
          ],
        ),
      ),
    );
  }
}
