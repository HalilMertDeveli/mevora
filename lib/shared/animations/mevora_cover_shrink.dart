import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/shared/animations/mevora_motion_size.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';

/// Compact transition accent — never a full-screen cover.
///
/// [progress] 0 = badge visible, 1 = gone. Content underneath stays readable.
class MevoraCoverShrinkOverlay extends StatelessWidget {
  const MevoraCoverShrinkOverlay({super.key, required this.progress});

  final double progress;

  static const overlayKey = ValueKey<String>('mevoraCoverShrinkOverlay');
  static const double _hold = 0.08;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    if (t >= 0.999) {
      return const SizedBox.shrink();
    }

    final shrinkT = ((t - _hold) / (1 - _hold)).clamp(0.0, 1.0);
    final scale = 1.0 - (0.28 * Curves.easeInCubic.transform(shrinkT));
    final opacity = t < 0.55
        ? 1.0
        : ((1.0 - t) / 0.45).clamp(0.0, 1.0);
    final size = MevoraMotionSize.transition(context);

    return IgnorePointer(
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 56,
            ),
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                filterQuality: FilterQuality.low,
                child: SizedBox(
                  key: overlayKey,
                  width: size,
                  height: size,
                  child: MevoraRiveAnimation(
                    asset: MevoraRiveAssets.pageAccent,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    fallback: SizedBox(
                      width: size * 0.45,
                      height: size * 0.45,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Replays a compact cover → shrink whenever [playToken] changes after
/// the first frame (shell tab switches).
class MevoraCoverShrinkGate extends StatefulWidget {
  const MevoraCoverShrinkGate({
    super.key,
    required this.playToken,
    required this.child,
    this.playOnFirstBuild = false,
  });

  final Object playToken;
  final Widget child;
  final bool playOnFirstBuild;

  @override
  State<MevoraCoverShrinkGate> createState() => _MevoraCoverShrinkGateState();
}

class _MevoraCoverShrinkGateState extends State<MevoraCoverShrinkGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Object _token;

  @override
  void initState() {
    super.initState();
    _token = widget.playToken;
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.coverShrink,
    );
    if (widget.playOnFirstBuild) {
      unawaited(_controller.forward());
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(MevoraCoverShrinkGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playToken != widget.playToken && _token != widget.playToken) {
      _token = widget.playToken;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        unawaited(_controller.forward(from: 0));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return MevoraCoverShrinkOverlay(progress: _controller.value);
          },
        ),
      ],
    );
  }
}
