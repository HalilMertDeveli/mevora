import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// The Discover card's answer to "why am I seeing this person?".
///
/// One human sentence (the strongest reason) and the top signals as tone
/// pills, with the overall score as a quiet ring. The whole strip opens the
/// full breakdown.
class DiscoveryCompatibilityScore extends StatelessWidget {
  const DiscoveryCompatibilityScore({
    super.key,
    required this.score,
    this.status = CompatibilityDisplayStatus.ready,
    this.reason,
    this.signals = const [],
    this.onWhyTap,
  });

  final int score;
  final CompatibilityDisplayStatus status;

  /// The single most telling reason, already localized.
  final String? reason;
  final List<CompatibilitySignal> signals;
  final VoidCallback? onWhyTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;

    if (status == CompatibilityDisplayStatus.calculating) {
      return Row(
        children: [
          const MevoraOrbitLoader(size: 24),
          const SizedBox(width: AppSpacing.s12),
          Text(l10n.compatCalculating, style: theme.textTheme.bodyMedium),
        ],
      );
    }
    if (status == CompatibilityDisplayStatus.unavailable) {
      return Text(l10n.compatUnavailable, style: theme.textTheme.bodyMedium);
    }

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.whyYouMatch.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: p.compatibility,
                  letterSpacing: 1,
                ),
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  reason!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 15,
                    height: 21 / 15,
                  ),
                ),
              ],
              if (signals.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                CompatibilitySignalPills(signals: signals, showScores: false),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        CompatibilityRing(score: score, size: 48),
        if (onWhyTap != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(MevoraIcons.chevronRight, size: 18, color: p.textTertiary),
        ],
      ],
    );

    if (onWhyTap == null) return body;
    return Semantics(
      button: true,
      label: l10n.whyYouMatch,
      child: InkWell(
        onTap: onWhyTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: body,
        ),
      ),
    );
  }
}

/// Compact compatibility pill for secondary surfaces (details header).
class CompatibilityDiscoverBadge extends StatelessWidget {
  const CompatibilityDiscoverBadge({
    super.key,
    required this.score,
    this.status = CompatibilityDisplayStatus.ready,
    this.onTap,
  });

  final int score;
  final CompatibilityDisplayStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (status) {
      CompatibilityDisplayStatus.calculating => l10n.compatCalculating,
      CompatibilityDisplayStatus.unavailable => l10n.compatUnavailable,
      CompatibilityDisplayStatus.ready => l10n.compatDiscoverBadge(score),
    };
    final pill = MevoraPill(
      label: label,
      icon: status == CompatibilityDisplayStatus.unavailable
          ? MevoraIcons.info
          : MevoraIcons.compatibility,
      tone: MevoraTone.compatibility,
    );
    final canTap = status == CompatibilityDisplayStatus.ready && onTap != null;
    if (!canTap) return pill;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
          child: pill,
        ),
      ),
    );
  }
}
