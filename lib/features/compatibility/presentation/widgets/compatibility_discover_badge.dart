import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Compact, tappable compatibility indicator for discovery cards.
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
    final theme = Theme.of(context);

    final label = switch (status) {
      CompatibilityDisplayStatus.calculating => l10n.compatCalculating,
      CompatibilityDisplayStatus.unavailable => l10n.compatUnavailable,
      CompatibilityDisplayStatus.ready => l10n.compatDiscoverBadge(score),
    };

    final canTap = status == CompatibilityDisplayStatus.ready && onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canTap ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            gradient: LinearGradient(
              colors: [
                AppColors.accentPrimary.withValues(alpha: 0.22),
                AppColors.softPurple.withValues(alpha: 0.14),
              ],
            ),
            border: Border.all(color: AppColors.glassBorder),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == CompatibilityDisplayStatus.calculating)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  status == CompatibilityDisplayStatus.unavailable
                      ? Icons.info_outline
                      : Icons.auto_awesome,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
