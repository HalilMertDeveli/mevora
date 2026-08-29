import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/theme/app_colors.dart';

class AnimatedCompatibilityScore extends StatefulWidget {
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
  State<AnimatedCompatibilityScore> createState() =>
      _AnimatedCompatibilityScoreState();
}

class _AnimatedCompatibilityScoreState extends State<AnimatedCompatibilityScore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _score;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.medium,
    );
    _score = IntTween(begin: 0, end: widget.target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1, curve: Curves.easeOut),
    );
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayStyle = widget.compact
        ? theme.textTheme.headlineSmall
        : theme.textTheme.displayMedium;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Column(
            children: [
              Text(
                '${_score.value}%',
                style: displayStyle?.copyWith(
                  color: AppColors.softGreen,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
