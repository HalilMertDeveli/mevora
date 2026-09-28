import 'package:flutter/material.dart';
import 'package:mevora/core/extensions/string_extensions.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_typography.dart';
import 'package:mevora/core/theme/mevora_icons.dart';

/// A person's portrait. Falls back to serif initials on a warm tint derived
/// from the name, so two people without photos never look identical.
class MevoraAvatar extends StatelessWidget {
  const MevoraAvatar({
    super.key,
    this.image,
    this.name,
    this.size = 56,
    this.isVerified = false,
    this.showOnlineIndicator = false,
    this.ring = false,
    this.semanticLabel,
  });

  final ImageProvider? image;
  final String? name;
  final double size;
  final bool isVerified;
  final bool showOnlineIndicator;

  /// A linen ring separating the portrait from busy backgrounds.
  final bool ring;
  final String? semanticLabel;

  static const _tints = [
    (AppColors.emberSoft, AppColors.emberInk),
    (AppColors.sageSoft, AppColors.sageInk),
    (AppColors.duskSoft, AppColors.duskInk),
    (AppColors.marigoldSoft, AppColors.marigoldInk),
    (AppColors.roseSoft, AppColors.emberInk),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final initials = (name ?? '').initials;
    final seed = (name ?? '').codeUnits.fold<int>(0, (a, b) => a + b);
    final (bg, fg) = _tints[seed % _tints.length];

    Widget fallback() => ColoredBox(
      color: bg,
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
            fontFamily: AppTypography.displayFontFamily,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.36,
            height: 1,
            color: fg,
          ),
        ),
      ),
    );

    final portrait = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: image == null
            ? fallback()
            : Image(
                image: image!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => fallback(),
              ),
      ),
    );

    final badge = (size * 0.34).clamp(14.0, 28.0);
    return Semantics(
      label: semanticLabel ?? name,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (ring)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.background, width: 3),
                ),
                child: portrait,
              )
            else
              portrait,
            if (isVerified)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    color: p.surface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    MevoraIcons.verified,
                    size: badge * 0.86,
                    color: p.compatibility,
                  ),
                ),
              ),
            if (showOnlineIndicator)
              Positioned(
                right: isVerified ? badge * 0.9 : size * 0.02,
                bottom: size * 0.02,
                child: Container(
                  width: size * 0.24,
                  height: size * 0.24,
                  decoration: BoxDecoration(
                    color: p.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
