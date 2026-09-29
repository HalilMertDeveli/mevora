import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// A rounded horizontal meter (0–1): onboarding progress, genre share,
/// category fit. Animates between values.
class MevoraMeter extends StatelessWidget {
  const MevoraMeter({
    super.key,
    required this.value,
    this.tone = MevoraTone.accent,
    this.height = 6,
    this.semanticLabel,
    this.trackColor,
  });

  final double value;
  final MevoraTone tone;
  final double height;
  final String? semanticLabel;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final c = mevoraToneColors(context, tone);
    final clamped = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(clamped * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: trackColor ?? context.palette.surfaceMuted),
              TweenAnimationBuilder<double>(
                tween: Tween(end: clamped),
                duration: AppDurations.normal,
                curve: AppCurves.standard,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.strong,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
