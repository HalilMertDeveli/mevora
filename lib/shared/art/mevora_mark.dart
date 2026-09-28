import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_typography.dart';

/// The Mevora mark: two circles and the space they share.
///
/// It is the product in one shape — Mevora shows you the overlap between two
/// people, not a catalogue of them. The lens is always ember; the rings follow
/// the surface they sit on.
class MevoraMark extends StatelessWidget {
  const MevoraMark({super.key, this.size = 40, this.onMedia = false});

  final double size;

  /// Draw white rings for use on photography or the ink surface.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final ring = onMedia ? AppColors.onMedia : context.palette.textPrimary;
    return Semantics(
      label: AppConstants.appName,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: MevoraMarkPainter(ring: ring, lens: AppColors.ember),
        ),
      ),
    );
  }
}

/// Paints the mark into any square. [overlap] 0 → circles apart, 1 → the
/// resting logo; used by the loader and the match moment to animate it.
class MevoraMarkPainter extends CustomPainter {
  const MevoraMarkPainter({
    required this.ring,
    required this.lens,
    this.overlap = 1,
    this.rotation = 0,
    this.lensOpacity = 1,
  });

  final Color ring;
  final Color lens;
  final double overlap;
  final double rotation;
  final double lensOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final stroke = s * 0.085;
    final r = s * 0.27;
    // Resting distance between centres gives a lens ~40% of a circle wide.
    final restingGap = r * 1.05;
    final apartGap = r * 2.6;
    final gap = apartGap + (restingGap - apartGap) * overlap.clamp(0, 1);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final a = Offset(-gap / 2, 0);
    final b = Offset(gap / 2, 0);

    if (lensOpacity > 0 && gap < r * 2) {
      final lensPath = Path.combine(
        PathOperation.intersect,
        Path()..addOval(Rect.fromCircle(center: a, radius: r)),
        Path()..addOval(Rect.fromCircle(center: b, radius: r)),
      );
      canvas.drawPath(
        lensPath,
        Paint()..color = lens.withValues(alpha: lens.a * lensOpacity),
      );
    }

    final ringPaint = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;
    canvas.drawCircle(a, r, ringPaint);
    canvas.drawCircle(b, r, ringPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MevoraMarkPainter old) =>
      old.ring != ring ||
      old.lens != lens ||
      old.overlap != overlap ||
      old.rotation != rotation ||
      old.lensOpacity != lensOpacity;
}

/// The mark settling into place once: the circles arrive apart and come to
/// rest overlapping as the lens fills. Used on the welcome and splash screens.
class MevoraMarkIntro extends StatefulWidget {
  const MevoraMarkIntro({super.key, this.size = 112});

  final double size;

  @override
  State<MevoraMarkIntro> createState() => _MevoraMarkIntroState();
}

class _MevoraMarkIntroState extends State<MevoraMarkIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
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
    final ring = context.palette.textPrimary;
    return Semantics(
      label: AppConstants.appName,
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final move = Curves.easeOutCubic.transform(
                (_c.value / 0.75).clamp(0, 1),
              );
              final lens = Curves.easeOut.transform(
                ((_c.value - 0.45) / 0.55).clamp(0, 1),
              );
              return CustomPaint(
                painter: MevoraMarkPainter(
                  ring: ring,
                  lens: AppColors.ember,
                  overlap: move,
                  lensOpacity: lens,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Mark + lowercase serif wordmark.
class MevoraLogo extends StatelessWidget {
  const MevoraLogo({
    super.key,
    this.size = 56,
    this.onMedia = false,
    this.showWordmark = true,
    this.axis = Axis.vertical,
  });

  final double size;
  final bool onMedia;
  final bool showWordmark;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final color = onMedia ? AppColors.onMedia : context.palette.textPrimary;
    final mark = MevoraMark(size: size, onMedia: onMedia);
    if (!showWordmark) return mark;
    final wordmark = ExcludeSemantics(
      child: Text(
        AppConstants.appName.toLowerCase(),
        style: TextStyle(
          fontFamily: AppTypography.displayFontFamily,
          fontWeight: FontWeight.w600,
          fontSize: axis == Axis.vertical ? size * 0.5 : size * 0.62,
          letterSpacing: -0.5,
          height: 1,
          color: color,
        ),
      ),
    );
    return axis == Axis.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              SizedBox(height: size * 0.22),
              wordmark,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              SizedBox(width: size * 0.2),
              wordmark,
            ],
          );
  }
}
