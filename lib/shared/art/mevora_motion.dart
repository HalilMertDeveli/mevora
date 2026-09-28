import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/art/mevora_mark.dart';

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Mevora's loading indicator: the two circles of the mark drift apart and
/// find each other again. Used instead of a bare spinner everywhere the app
/// is waiting on something that is not a single button.
class MevoraOrbitLoader extends StatefulWidget {
  const MevoraOrbitLoader({super.key, this.size = 48, this.onMedia = false});

  final double size;
  final bool onMedia;

  @override
  State<MevoraOrbitLoader> createState() => _MevoraOrbitLoaderState();
}

class _MevoraOrbitLoaderState extends State<MevoraOrbitLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.value = 0.5;
      _c.stop();
    } else if (!_c.isAnimating) {
      unawaited(_c.repeat());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = widget.onMedia
        ? AppColors.onMedia
        : context.palette.textPrimary;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // Overlap breathes 0.35 → 1 → 0.35; the pair turns a half circle
            // per loop so the motion reads as orbiting, not pulsing.
            final wave = 0.5 - 0.5 * math.cos(_c.value * 2 * math.pi);
            final overlap = 0.35 + 0.65 * Curves.easeInOut.transform(wave);
            return CustomPaint(
              painter: MevoraMarkPainter(
                ring: ring,
                lens: AppColors.ember,
                overlap: overlap,
                rotation: _c.value * math.pi,
                lensOpacity: wave,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A circle that draws itself closed, then a check — for completion moments
/// (verified, Spotify connected, Premium active, profile complete).
class MevoraSuccessMark extends StatefulWidget {
  const MevoraSuccessMark({super.key, this.size = 88, this.color});

  final double size;
  final Color? color;

  @override
  State<MevoraSuccessMark> createState() => _MevoraSuccessMarkState();
}

class _MevoraSuccessMarkState extends State<MevoraSuccessMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppDurations.celebrate,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      unawaited(_c.forward());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.palette.success;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _SuccessPainter(t: _c.value, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessPainter extends CustomPainter {
  _SuccessPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final r = s * 0.36;
    final stroke = s * 0.06;
    final ringT = Curves.easeOutCubic.transform((t / 0.55).clamp(0, 1));
    final checkT = Curves.easeOutCubic.transform(
      ((t - 0.45) / 0.4).clamp(0, 1),
    );
    final burstT = ((t - 0.6) / 0.4).clamp(0.0, 1.0);

    canvas.drawCircle(
      c,
      r * (0.9 + 0.1 * ringT),
      Paint()..color = color.withValues(alpha: 0.12 * ringT),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * ringT,
      false,
      paint,
    );

    if (checkT > 0) {
      final p1 = c + Offset(-r * 0.42, r * 0.02);
      final p2 = c + Offset(-r * 0.1, r * 0.34);
      final p3 = c + Offset(r * 0.46, -r * 0.3);
      final first = (checkT / 0.4).clamp(0.0, 1.0);
      final second = ((checkT - 0.4) / 0.6).clamp(0.0, 1.0);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(
          p1.dx + (p2.dx - p1.dx) * first,
          p1.dy + (p2.dy - p1.dy) * first,
        );
      if (second > 0) {
        path.lineTo(
          p2.dx + (p3.dx - p2.dx) * second,
          p2.dy + (p3.dy - p2.dy) * second,
        );
      }
      canvas.drawPath(path, paint..strokeJoin = StrokeJoin.round);
    }

    if (burstT > 0 && burstT < 1) {
      final dot = Paint()..color = color.withValues(alpha: 1 - burstT);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + math.pi / 8;
        final d = r * (1.15 + 0.35 * Curves.easeOut.transform(burstT));
        canvas.drawCircle(
          c + Offset(math.cos(a), math.sin(a)) * d,
          stroke * 0.45 * (1 - burstT),
          dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SuccessPainter old) => old.t != t || old.color != color;
}

/// Boost activation: the bolt lands and two rings travel outward — "your
/// profile is being shown further". Plays once.
class MevoraBoostBurst extends StatefulWidget {
  const MevoraBoostBurst({super.key, this.size = 96});

  final double size;

  @override
  State<MevoraBoostBurst> createState() => _MevoraBoostBurstState();
}

class _MevoraBoostBurstState extends State<MevoraBoostBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      unawaited(_c.forward());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final pop = AppCurves.emphasized.transform(
                (_c.value / 0.45).clamp(0, 1),
              );
              return CustomPaint(
                painter: _RingsPainter(
                  t: _c.value,
                  soft: scheme.primaryContainer,
                  strong: scheme.primary,
                ),
                child: Center(
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * pop,
                    child: Icon(
                      MevoraIcons.boostActive,
                      size: widget.size * 0.4,
                      color: scheme.primary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.t, required this.soft, required this.strong});

  final double t;
  final Color soft;
  final Color strong;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    canvas.drawCircle(c, base * 0.62, Paint()..color = soft);
    for (final delay in const [0.2, 0.42]) {
      final k = ((t - delay) / 0.58).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      final eased = Curves.easeOut.transform(k);
      canvas.drawCircle(
        c,
        base * (0.62 + 0.38 * eased),
        Paint()
          ..color = strong.withValues(alpha: 0.5 * (1 - k))
          ..style = PaintingStyle.stroke
          ..strokeWidth = base * 0.04,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}
