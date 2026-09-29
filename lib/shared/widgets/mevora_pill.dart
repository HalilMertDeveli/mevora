import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';

/// The colour a pill, badge or banner speaks in. Each Mevora signal has its
/// own tone so "music" and "humor" read differently at a glance.
enum MevoraTone {
  neutral,
  accent,
  compatibility,
  music,
  humor,
  premium,
  match,
  success,
  warning,
  error,
  info,

  /// White on translucent dark — for pills over photography.
  onMedia,
}

/// Resolved colours for a [MevoraTone].
({Color fg, Color bg, Color strong}) mevoraToneColors(
  BuildContext context,
  MevoraTone tone,
) {
  final p = context.palette;
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    MevoraTone.neutral => (
      fg: p.textSecondary,
      bg: p.surfaceMuted,
      strong: p.textPrimary,
    ),
    MevoraTone.accent => (
      fg: scheme.onPrimaryContainer,
      bg: scheme.primaryContainer,
      strong: scheme.primary,
    ),
    MevoraTone.compatibility => (
      fg: p.onCompatibilityContainer,
      bg: p.compatibilityContainer,
      strong: p.compatibility,
    ),
    MevoraTone.music => (
      fg: p.onMusicContainer,
      bg: p.musicContainer,
      strong: p.music,
    ),
    MevoraTone.humor => (
      fg: p.onHumorContainer,
      bg: p.humorContainer,
      strong: p.humor,
    ),
    MevoraTone.premium => (
      fg: p.onPremiumContainer,
      bg: p.premiumContainer,
      strong: p.premium,
    ),
    MevoraTone.match => (fg: p.match, bg: p.matchContainer, strong: p.match),
    MevoraTone.success => (
      fg: p.success,
      bg: p.successContainer,
      strong: p.success,
    ),
    MevoraTone.warning => (
      fg: p.warning,
      bg: p.warningContainer,
      strong: p.warning,
    ),
    MevoraTone.error => (fg: p.error, bg: p.errorContainer, strong: p.error),
    MevoraTone.info => (fg: p.info, bg: p.infoContainer, strong: p.info),
    MevoraTone.onMedia => (
      fg: AppColors.onMedia,
      bg: AppColors.mediaControl,
      strong: AppColors.onMedia,
    ),
  };
}

/// A small read-only label: status, a signal, a count. Not interactive — use
/// [MevoraChip] for choices.
class MevoraPill extends StatelessWidget {
  const MevoraPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = MevoraTone.neutral,
    this.dense = false,
    this.semanticLabel,
    this.iconSemanticLabel,
  });

  final String label;
  final IconData? icon;
  final MevoraTone tone;
  final bool dense;
  final String? semanticLabel;

  /// Gives the icon its own accessible name (e.g. a verified check that
  /// means something on its own) instead of merging it into the label.
  final String? iconSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = mevoraToneColors(context, tone);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: c.fg,
      fontSize: dense ? 12 : 13,
      height: 16 / 13,
    );
    return Semantics(
      label: iconSemanticLabel == null ? (semanticLabel ?? label) : null,
      excludeSemantics: iconSemanticLabel == null,
      container: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? AppSpacing.sm : AppSpacing.s12 - 2,
          vertical: dense ? AppSpacing.xxs : AppSpacing.xs + 1,
        ),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: tone == MevoraTone.onMedia
              ? Border.all(color: AppColors.mediaControlBorder)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Semantics(
                container: iconSemanticLabel != null,
                label: iconSemanticLabel,
                child: ExcludeSemantics(
                  child: Icon(icon, size: dense ? 12 : 14, color: c.strong),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tinted square with a glyph — leads list rows and feature cards.
class MevoraIconBadge extends StatelessWidget {
  const MevoraIconBadge({
    super.key,
    required this.icon,
    this.tone = MevoraTone.neutral,
    this.size = 40,
    this.circle = false,
    this.background,
  });

  final IconData icon;
  final MevoraTone tone;
  final double size;
  final bool circle;

  /// Overrides the tone's container — for badges sitting on a tinted card.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = mevoraToneColors(context, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? c.bg,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: c.strong),
    );
  }
}

/// A small count badge (unread messages, new likes).
class MevoraCountBadge extends StatelessWidget {
  const MevoraCountBadge({super.key, required this.count, this.semanticLabel});

  final int count;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = count > 99 ? '99+' : '$count';
    return Semantics(
      label: semanticLabel ?? text,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onPrimary,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
