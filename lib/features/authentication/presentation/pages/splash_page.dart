import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_typography.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/components/mevora_logo.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.night,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1220),
              AppColors.night,
              Color(0xFF0E0A10),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IgnorePointer(
                    child: MevoraRiveAnimation(
                      asset: MevoraRiveAssets.splash,
                      width: 168,
                      height: 168,
                      fit: BoxFit.contain,
                      semanticsLabel: l10n.appName,
                      fallback: const MevoraLogo(
                        size: 88,
                        onDark: true,
                        showWordmark: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    AppConstants.appName.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: AppTypography.displayFontFamily,
                      color: Color(0xFFF4EEE8),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.tagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFD8CFD6),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    l10n.preparingMevora,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFD8CFD6),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  MevoraRiveAnimation(
                    asset: MevoraRiveAssets.loading,
                    width: 40,
                    height: 40,
                    semanticsLabel: l10n.preparingMevora,
                    fallback: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
