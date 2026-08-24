import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Spotlight badge for boosted profiles on discovery cards.
class DiscoveryBoostBadge extends StatelessWidget {
  const DiscoveryBoostBadge({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? AppSpacing.xs : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.accentPrimary,
            AppColors.softPurple,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt_rounded,
            size: compact ? 14 : 16,
            color: AppColors.primaryText,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l10n.boostDiscoverBadge,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
