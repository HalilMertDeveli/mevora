import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/theme/app_radii.dart';

class MevoraLogo extends StatelessWidget {
  const MevoraLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          alignment: Alignment.center,
          child: Text(
            'M',
            style: TextStyle(
              color: colors.onPrimary,
              fontSize: size * 0.46,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(height: size * 0.2),
        Text(
          AppConstants.appName.toUpperCase(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            letterSpacing: 4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
