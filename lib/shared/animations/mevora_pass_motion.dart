import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';

/// Pass motion: fades and translates the child away. Plays once.
class MevoraPassMotion extends StatelessWidget {
  const MevoraPassMotion({
    super.key,
    required this.child,
    this.active = false,
  });

  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppDurations.pass,
      opacity: active ? 0 : 1,
      curve: Curves.easeOut,
      child: AnimatedSlide(
        duration: AppDurations.pass,
        offset: active ? const Offset(-0.18, 0.02) : Offset.zero,
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
