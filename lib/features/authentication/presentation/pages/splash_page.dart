import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_typography.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_mark.dart';
import 'package:mevora/shared/art/mevora_motion.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const MevoraMarkIntro(size: 96),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppConstants.appName.toLowerCase(),
                style: TextStyle(
                  fontFamily: AppTypography.displayFontFamily,
                  color: p.textPrimary,
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                  height: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                l10n.tagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: p.textSecondary,
                ),
              ),
              const Spacer(flex: 3),
              Semantics(
                label: l10n.preparingMevora,
                liveRegion: true,
                child: const MevoraOrbitLoader(size: 32),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(l10n.preparingMevora, style: theme.textTheme.bodySmall),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
