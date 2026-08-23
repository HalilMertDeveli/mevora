import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_shadows.dart';

enum MevoraCardEmphasis { standard, quiet, elevated }

class MevoraCard extends StatelessWidget {
  const MevoraCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.emphasis = MevoraCardEmphasis.standard,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final MevoraCardEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      child: child,
    );
    final showBorder = emphasis != MevoraCardEmphasis.elevated;
    final showShadow = emphasis != MevoraCardEmphasis.quiet;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: switch (emphasis) {
          MevoraCardEmphasis.elevated => theme.colorScheme.surfaceContainerHigh,
          MevoraCardEmphasis.quiet => theme.colorScheme.surfaceContainer,
          MevoraCardEmphasis.standard => theme.colorScheme.surfaceContainerLow,
        },
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: showBorder
            ? Border.all(
                color: theme.brightness == Brightness.dark
                    ? AppColors.glassBorder
                    : theme.colorScheme.outlineVariant,
              )
            : null,
        boxShadow: showShadow ? AppShadows.card(theme.brightness) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}
