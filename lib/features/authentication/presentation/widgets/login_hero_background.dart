import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';

/// Full-bleed login hero with optional slow Ken Burns zoom.
///
/// Background: `assets/images/login_background.jpg`
/// Source/license: see `assets/images/LOGIN_BACKGROUND_SOURCE.md`
/// (Unsplash photo-1516589178581-6cd7833ae3b2, Unsplash License).
class LoginHeroBackground extends StatefulWidget {
  const LoginHeroBackground({super.key, this.child});

  final Widget? child;

  /// Disabled in widget tests so [pumpAndSettle] can complete.
  static bool get kenBurnsEnabled =>
      !WidgetsBinding.instance.runtimeType.toString().contains(
        'TestWidgetsFlutterBinding',
      );

  @override
  State<LoginHeroBackground> createState() => _LoginHeroBackgroundState();
}

class _LoginHeroBackgroundState extends State<LoginHeroBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _kenBurns;

  @override
  void initState() {
    super.initState();
    if (LoginHeroBackground.kenBurnsEnabled) {
      _kenBurns = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 15),
      );
      unawaited(_kenBurns!.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _kenBurns?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kenBurns = _kenBurns;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (kenBurns == null)
          const _LoginPhoto(scale: 1)
        else
          AnimatedBuilder(
            animation: kenBurns,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(kenBurns.value);
              final scale = 1.0 + (0.04 * t);
              return _LoginPhoto(scale: scale);
            },
          ),
        const IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Opacity(
              opacity: 0.28,
              child: SizedBox(
                height: 280,
                width: double.infinity,
                child: MevoraRiveAnimation(
                  asset: MevoraRiveAssets.loginAmbient,
                  fit: BoxFit.cover,
                  fallback: SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        const _LoginGradientOverlay(),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _LoginPhoto extends StatelessWidget {
  const _LoginPhoto({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/images/login_background.jpg',
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          return const ColoredBox(color: AppColors.night);
        },
      ),
    );
  }
}

class _LoginGradientOverlay extends StatelessWidget {
  const _LoginGradientOverlay();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x66140F16),
            Color(0x33140F16),
            Color(0xCC140F16),
            Color(0xF2140F16),
          ],
          stops: [0.0, 0.28, 0.62, 1.0],
        ),
      ),
    );
  }
}
