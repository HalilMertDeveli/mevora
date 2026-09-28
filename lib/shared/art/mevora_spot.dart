import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The subjects Mevora illustrates. Each maps to one duotone glyph and one
/// signal colour, so an empty inbox always looks like an empty inbox.
enum MevoraArt {
  searching,
  emptyProfiles,
  emptyMatches,
  emptyMessages,
  emptyLikes,
  music,
  humor,
  compatibility,
  questions,
  location,
  photos,
  notifications,
  verification,
  premium,
  boost,
  success,
  error,
  offline,
  blocked,
  support,
  generic,
}

enum _Tone {
  ember,
  match,
  sage,
  dusk,
  marigold,
  brass,
  success,
  error,
  neutral,
}

({IconData icon, _Tone tone}) _spec(MevoraArt art) => switch (art) {
  MevoraArt.searching => (
    icon: PhosphorIconsDuotone.compass,
    tone: _Tone.ember,
  ),
  MevoraArt.emptyProfiles => (
    icon: PhosphorIconsDuotone.binoculars,
    tone: _Tone.ember,
  ),
  MevoraArt.emptyMatches => (
    icon: PhosphorIconsDuotone.heart,
    tone: _Tone.match,
  ),
  MevoraArt.emptyMessages => (
    icon: PhosphorIconsDuotone.chatsCircle,
    tone: _Tone.ember,
  ),
  MevoraArt.emptyLikes => (
    icon: PhosphorIconsDuotone.handHeart,
    tone: _Tone.match,
  ),
  MevoraArt.music => (icon: PhosphorIconsDuotone.vinylRecord, tone: _Tone.dusk),
  MevoraArt.humor => (
    icon: PhosphorIconsDuotone.maskHappy,
    tone: _Tone.marigold,
  ),
  MevoraArt.compatibility => (
    icon: PhosphorIconsDuotone.intersect,
    tone: _Tone.sage,
  ),
  MevoraArt.questions => (
    icon: PhosphorIconsDuotone.chatCircleDots,
    tone: _Tone.sage,
  ),
  MevoraArt.location => (icon: PhosphorIconsDuotone.mapPin, tone: _Tone.sage),
  MevoraArt.photos => (icon: PhosphorIconsDuotone.images, tone: _Tone.ember),
  MevoraArt.notifications => (
    icon: PhosphorIconsDuotone.bellRinging,
    tone: _Tone.ember,
  ),
  MevoraArt.verification => (
    icon: PhosphorIconsDuotone.sealCheck,
    tone: _Tone.sage,
  ),
  MevoraArt.premium => (
    icon: PhosphorIconsDuotone.crownSimple,
    tone: _Tone.brass,
  ),
  MevoraArt.boost => (icon: PhosphorIconsDuotone.lightning, tone: _Tone.ember),
  MevoraArt.success => (
    icon: PhosphorIconsDuotone.checkCircle,
    tone: _Tone.success,
  ),
  MevoraArt.error => (
    icon: PhosphorIconsDuotone.warningCircle,
    tone: _Tone.error,
  ),
  MevoraArt.offline => (
    icon: PhosphorIconsDuotone.cloudSlash,
    tone: _Tone.neutral,
  ),
  MevoraArt.blocked => (
    icon: PhosphorIconsDuotone.prohibit,
    tone: _Tone.neutral,
  ),
  MevoraArt.support => (icon: PhosphorIconsDuotone.lifebuoy, tone: _Tone.sage),
  MevoraArt.generic => (
    icon: PhosphorIconsDuotone.hourglassSimple,
    tone: _Tone.neutral,
  ),
};

({Color strong, Color soft}) _toneColors(BuildContext context, _Tone tone) {
  final p = context.palette;
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    _Tone.ember => (strong: scheme.primary, soft: scheme.primaryContainer),
    _Tone.match => (strong: p.match, soft: p.matchContainer),
    _Tone.sage => (strong: p.compatibility, soft: p.compatibilityContainer),
    _Tone.dusk => (strong: p.music, soft: p.musicContainer),
    _Tone.marigold => (strong: p.humor, soft: p.humorContainer),
    _Tone.brass => (strong: p.premium, soft: p.premiumContainer),
    _Tone.success => (strong: p.success, soft: p.successContainer),
    _Tone.error => (strong: p.error, soft: p.errorContainer),
    _Tone.neutral => (strong: p.textSecondary, soft: p.surfaceMuted),
  };
}

/// A spot illustration: a soft halo in the subject's signal colour, the
/// subject's duotone glyph, and three small satellites.
///
/// With [animate] the satellites drift and the halo breathes — used where the
/// app is waiting (searching, analysing). Static everywhere else. Motion is
/// dropped automatically when the OS asks for reduced motion.
class MevoraSpot extends StatefulWidget {
  const MevoraSpot({
    super.key,
    required this.art,
    this.size = 112,
    this.animate = false,
  });

  final MevoraArt art;
  final double size;
  final bool animate;

  @override
  State<MevoraSpot> createState() => _MevoraSpotState();
}

class _MevoraSpotState extends State<MevoraSpot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(MevoraSpot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduce) {
      if (!_controller.isAnimating) unawaited(_controller.repeat());
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec(widget.art);
    final colors = _toneColors(context, spec.tone);
    final size = widget.size;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => CustomPaint(
              painter: _HaloPainter(
                soft: colors.soft,
                strong: colors.strong,
                t: _controller.value,
              ),
              child: child,
            ),
            child: Center(
              child: PhosphorIcon(
                spec.icon,
                size: size * 0.42,
                color: colors.strong,
                duotoneSecondaryOpacity: 1,
                duotoneSecondaryColor: colors.strong.withValues(alpha: 0.28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.soft, required this.strong, required this.t});

  final Color soft;
  final Color strong;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    final breathe = 1 + 0.025 * math.sin(t * 2 * math.pi * 2);

    canvas.drawCircle(c, base * 0.78 * breathe, Paint()..color = soft);
    canvas.drawCircle(
      c,
      base * 0.94,
      Paint()
        ..color = soft
        ..style = PaintingStyle.stroke
        ..strokeWidth = base * 0.025,
    );

    // Three satellites on the outer ring, a slow orbit when animating.
    const phases = [0.12, 0.45, 0.78];
    const radii = [0.07, 0.045, 0.055];
    for (var i = 0; i < phases.length; i++) {
      final angle = (phases[i] + t) * 2 * math.pi - math.pi / 2;
      final p = c + Offset(math.cos(angle), math.sin(angle)) * base * 0.94;
      canvas.drawCircle(
        p,
        base * radii[i],
        Paint()..color = i == 0 ? strong : strong.withValues(alpha: 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.t != t || old.soft != soft || old.strong != strong;
}
