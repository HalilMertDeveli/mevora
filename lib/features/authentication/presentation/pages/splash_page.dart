import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_decorations.dart';
import 'package:mevora/core/theme/app_typography.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_motion_size.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/components/mevora_logo.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: colors.surface,
      body: DecoratedBox(
        decoration: AppDecorations.ambientScreen(brightness: theme.brightness),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Visibility(
                    visible: false,
                    replacement: MevoraLogo(
                      size: 88,
                      onDark: isDark,
                      showWordmark: false,
                    ),
                    child: IgnorePointer(
                      child: MevoraRiveAnimation(
                        asset: MevoraRiveAssets.splash,
                        width: 168,
                        height: 168,
                        fit: BoxFit.contain,
                        fallback: MevoraLogo(
                          size: 88,
                          onDark: isDark,
                          showWordmark: false,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    AppConstants.appName.toUpperCase(),
                    style: TextStyle(
                      fontFamily: AppTypography.displayFontFamily,
                      color: colors.onSurface,
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
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    l10n.preparingMevora,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Builder(
                    builder: (context) {
                      final size = MevoraMotionSize.loading(context);
                      return MevoraRiveAnimation(
                        asset: MevoraRiveAssets.loading,
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        semanticsLabel: l10n.preparingMevora,
                        fallback: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colors.primary,
                          ),
                        ),
                      );
                    },
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
