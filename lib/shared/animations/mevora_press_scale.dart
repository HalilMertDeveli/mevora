import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';

/// Subtle press feedback for buttons: 150–200ms scale and opacity.
class MevoraPressScale extends StatefulWidget {
  const MevoraPressScale({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<MevoraPressScale> createState() => _MevoraPressScaleState();
}

class _MevoraPressScaleState extends State<MevoraPressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.button,
    );
    _scale = Tween<double>(begin: 1, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 1, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _forward() {
    if (widget.enabled) {
      unawaited(_controller.forward());
    }
  }

  void _reverse() {
    unawaited(_controller.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _forward(),
      onPointerUp: (_) => _reverse(),
      onPointerCancel: (_) => _reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacity.value,
            child: Transform.scale(scale: _scale.value, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}
