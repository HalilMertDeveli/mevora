import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';

/// A short, non-looping heart that scales in then fades. Used on Like.
class MevoraLikeBurst extends StatefulWidget {
  const MevoraLikeBurst({
    super.key,
    required this.play,
    this.color,
  });

  final bool play;
  final Color? color;

  @override
  State<MevoraLikeBurst> createState() => _MevoraLikeBurstState();
}

class _MevoraLikeBurstState extends State<MevoraLikeBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.like,
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.15), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1), weight: 45),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 60),
    ]).animate(_controller);
    if (widget.play) {
      unawaited(_controller.forward());
    }
  }

  @override
  void didUpdateWidget(covariant MevoraLikeBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) {
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.secondary;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacity.value,
            child: Transform.scale(scale: _scale.value, child: child),
          );
        },
        child: Icon(Icons.favorite_rounded, size: 72, color: color),
      ),
    );
  }
}
