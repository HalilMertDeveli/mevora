import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';

class AnimatedCompatibilityScore extends StatefulWidget {
  const AnimatedCompatibilityScore({
    super.key,
    required this.target,
    required this.label,
  });

  final int target;
  final String label;

  @override
  State<AnimatedCompatibilityScore> createState() =>
      _AnimatedCompatibilityScoreState();
}

class _AnimatedCompatibilityScoreState extends State<AnimatedCompatibilityScore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _score;

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
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _score,
      builder: (context, child) {
        return Column(
          children: [
            Text(
              '${_score.value}%',
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(widget.label, style: theme.textTheme.bodyLarge),
          ],
        );
      },
    );
  }
}
