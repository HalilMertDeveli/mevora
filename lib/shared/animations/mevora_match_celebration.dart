import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';

/// Premium, one-shot match moment: two portraits meet, then MATCH appears.
class MevoraMatchCelebration extends StatefulWidget {
  const MevoraMatchCelebration({
    super.key,
    required this.leftName,
    required this.rightName,
    this.leftImage,
    this.rightImage,
    this.onCompleted,
  });

  final String leftName;
  final String rightName;
  final ImageProvider? leftImage;
  final ImageProvider? rightImage;
  final VoidCallback? onCompleted;

  @override
  State<MevoraMatchCelebration> createState() => _MevoraMatchCelebrationState();
}

class _MevoraMatchCelebrationState extends State<MevoraMatchCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _approach;
  late final Animation<double> _labelOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.match,
    );
    _approach = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
    );
    _labelOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1, curve: Curves.easeOut),
    );
    unawaited(
      _controller.forward().whenComplete(() {
        widget.onCompleted?.call();
      }),
    );
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
      animation: _controller,
      builder: (context, child) {
        final gap = 48 - (_approach.value * 20);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MevoraAvatar(
                  name: widget.leftName,
                  image: widget.leftImage,
                  size: 88,
                ),
                SizedBox(width: gap),
                MevoraAvatar(
                  name: widget.rightName,
                  image: widget.rightImage,
                  size: 88,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Opacity(
              opacity: _labelOpacity.value,
              child: Text(
                'MATCH',
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 6,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
