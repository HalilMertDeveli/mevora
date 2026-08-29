import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_decorations.dart';

/// Calm warm-cream auth backdrop — no dating-app photo hero.
class LoginHeroBackground extends StatelessWidget {
  const LoginHeroBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: AppDecorations.ambientScreen(brightness: brightness),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.amber.withValues(alpha: 0.06),
                  Colors.transparent,
                  AppColors.softGreen.withValues(alpha: 0.04),
                ],
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
