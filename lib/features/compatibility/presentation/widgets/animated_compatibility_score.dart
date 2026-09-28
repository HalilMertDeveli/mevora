import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';

/// The overall score: a ring that fills once, with its label beneath.
class AnimatedCompatibilityScore extends StatelessWidget {
  const AnimatedCompatibilityScore({
    super.key,
    required this.target,
    required this.label,
    this.compact = false,
  });

  final int target;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompatibilityRing(score: target, size: compact ? 56 : 80),
        const SizedBox(height: AppSpacing.sm),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
