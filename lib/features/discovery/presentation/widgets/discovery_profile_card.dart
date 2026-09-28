import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_decorations.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_shadows.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/presentation/compatibility_l10n.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_discover_badge.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_category_bar.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// The Discover card.
///
/// The person owns the card: a full-bleed portrait with their name set in
/// the serif over a soft scrim. Beneath it, one strip answers "why is Mevora
/// showing me this person?" — a reason in words, the top signals, and a
/// quiet score ring. Everything else lives one tap away on the profile.
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
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    final photo = candidate.photoUrl;
    final distance = candidate.distanceKm != null
        ? L10nFormat.distance(l10n, candidate.distanceKm!)
        : candidate.distanceLabel;
    final place = [
      if (candidate.city != null && candidate.city!.isNotEmpty) candidate.city!,
      if (distance != null && distance.isNotEmpty) distance,
    ].join(' · ');
    final showWhy =
        candidate.compatibilityStatus ==
            CompatibilityDisplayStatus.calculating ||
        candidate.compatibilityStatus ==
            CompatibilityDisplayStatus.unavailable ||
        candidate.hasCompatibilityScore;
    // Backend reasons are fixed English codes: localize them, and drop any
    // this build does not know rather than show raw English.
    final localizedReasons = CompatibilityL10n.serverReasons(
      l10n,
      candidate.compatibilityReasons,
      relationshipGoal: candidate.relationshipGoal,
    );
    final reason = localizedReasons.isNotEmpty
        ? localizedReasons.first
        : candidate.sharedInterests.isNotEmpty
        ? l10n.sharedHobbiesCount(candidate.sharedInterests.length)
        : null;
    final radius = BorderRadius.circular(AppRadii.card);

    return Semantics(
      container: true,
      label: '${candidate.displayName}, ${candidate.age}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: p.surface,
          boxShadow: AppShadows.discoveryCard(theme.brightness),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (photo == null)
                          const PhotoUnavailablePlaceholder()
                        else
                          DiscoveryNetworkImage(url: photo),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppDecorations.photoScrim(),
                          ),
                        ),
                        if (candidate.isBoosted)
                          const Positioned(
                            top: AppSpacing.md,
                            left: AppSpacing.md,
                            child: DiscoveryBoostBadge(),
                          ),
                        Positioned(
                          left: AppSpacing.s20,
                          right: AppSpacing.s20,
                          bottom: AppSpacing.md,
                          child: _Identity(
                            name: candidate.displayName,
                            age: candidate.age,
                            place: place,
                            verified: candidate.isVerified,
                            verifiedLabel: l10n.profileVerifiedBadge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showWhy)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.s12,
                      AppSpacing.s12,
                      AppSpacing.s12,
                    ),
                    child: DiscoveryCompatibilityScore(
                      score: candidate.compatibilityScore,
                      status: candidate.compatibilityStatus,
                      reason: reason,
                      signals: discoverySignals(candidate, limit: 3),
                      onWhyTap: candidate.hasCompatibilityScore
                          ? onWhyTap
                          : null,
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

class _Identity extends StatelessWidget {
  const _Identity({
    required this.name,
    required this.age,
    required this.place,
    required this.verified,
    required this.verifiedLabel,
  });

  final String name;
  final int age;
  final String place;
  final bool verified;
  final String verifiedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                '$name, $age',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: AppColors.onMedia,
                ),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                MevoraIcons.verified,
                size: 22,
                color: AppColors.onMedia,
                semanticLabel: verifiedLabel,
              ),
            ],
          ],
        ),
        if (place.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              const Icon(
                MevoraIcons.location,
                size: 16,
                color: AppColors.onMediaMuted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onMediaMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
