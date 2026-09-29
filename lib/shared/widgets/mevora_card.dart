import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_shadows.dart';

/// * [standard] — white card with a hairline, the default container.
/// * [quiet] — sand fill, no line: secondary information inside a page.
/// * [elevated] — floats (soft shadow, no line): one hero card per screen.
/// * [outline] — transparent with a line: optional / not-yet-filled content.
enum MevoraCardEmphasis { standard, quiet, elevated, outline }

class MevoraCard extends StatelessWidget {
  const MevoraCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.emphasis = MevoraCardEmphasis.standard,
    this.color,
    this.radius = AppRadii.lg,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final MevoraCardEmphasis emphasis;

  /// Tinted cards (a signal container) — overrides the emphasis fill.
  final Color? color;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final brightness = Theme.of(context).brightness;
    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      child: child,
    );

    final fill =
        color ??
        switch (emphasis) {
          MevoraCardEmphasis.quiet => p.surfaceMuted,
          MevoraCardEmphasis.outline => Colors.transparent,
          _ => p.surface,
        };
    final border = switch (emphasis) {
      MevoraCardEmphasis.standard when color == null => Border.all(
        color: p.border,
      ),
      MevoraCardEmphasis.outline => Border.all(color: p.borderStrong),
      _ => null,
    };

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: border,
        boxShadow: emphasis == MevoraCardEmphasis.elevated
            ? AppShadows.card(brightness)
            : null,
      ),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: content,
              ),
            ),
    );
    if (semanticLabel != null || onTap != null) {
      card = Semantics(
        button: onTap != null,
        label: semanticLabel,
        child: card,
      );
    }
    return Padding(padding: margin ?? EdgeInsets.zero, child: card);
  }
}
