import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';

enum MevoraMotionKind { empty, loading, success }

/// Flutter motion used when a Rive `.riv` asset is not bundled.
/// The app must never hang or crash because of a missing animation file.
class MevoraStatusMotion extends StatefulWidget {
  const MevoraStatusMotion({
    super.key,
    required this.kind,
    this.label,
    this.riveAsset,
  });

  final MevoraMotionKind kind;
  final String? label;
  final String? riveAsset;

  @override
  State<MevoraStatusMotion> createState() => _MevoraStatusMotionState();
}

class _MevoraStatusMotionState extends State<MevoraStatusMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.kind == MevoraMotionKind.loading ||
        widget.kind == MevoraMotionKind.empty) {
      unawaited(_controller.repeat(reverse: true));
    } else {
      unawaited(_controller.forward());
    }
  }

  @override
  void didUpdateWidget(MevoraStatusMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind == widget.kind) {
      return;
    }
    if (widget.kind == MevoraMotionKind.success) {
      _controller.duration = const Duration(milliseconds: 600);
      unawaited(_controller.forward(from: 0));
    } else {
      _controller.duration = const Duration(milliseconds: 1400);
      unawaited(_controller.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (widget.kind) {
      MevoraMotionKind.empty => Icons.add_a_photo_outlined,
      MevoraMotionKind.loading => Icons.hourglass_top_outlined,
      MevoraMotionKind.success => Icons.check_circle_outline,
    };
    return Column(
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 0.45, end: 1).animate(_controller),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            ),
            child: widget.riveAsset == null
                ? Icon(icon, size: 56, color: theme.colorScheme.primary)
                : MevoraRiveAnimation(
                    asset: widget.riveAsset!,
                    width: 56,
                    height: 56,
                    fallback: Icon(
                      icon,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                  ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.label!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}
