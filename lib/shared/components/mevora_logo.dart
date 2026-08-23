import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_typography.dart';

class MevoraLogo extends StatelessWidget {
  const MevoraLogo({
    super.key,
    this.size = 64,
    this.onDark = false,
    this.showWordmark = true,
  });

  final double size;
  final bool onDark;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final markColor = onDark ? AppColors.primaryText : colors.primary;
    final onMark = onDark ? AppColors.background : colors.onPrimary;
    final wordmarkColor = onDark
        ? AppColors.primaryText
        : (Theme.of(context).textTheme.titleMedium?.color ?? colors.onSurface);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: markColor,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          alignment: Alignment.center,
          child: Text(
            'M',
            style: TextStyle(
              fontFamily: AppTypography.displayFontFamily,
              color: onMark,
              fontSize: size * 0.46,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        if (showWordmark) ...[
          SizedBox(height: size * 0.2),
          Text(
            AppConstants.appName.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTypography.displayFontFamily,
              color: wordmarkColor,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 5.5,
              height: 1.1,
            ),
          ),
        ],
      ],
    );
  }
}
