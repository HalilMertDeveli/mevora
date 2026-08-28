import 'package:flutter/material.dart';

import 'package:mevora/core/responsive/responsive_breakpoints.dart';

/// Aspect ratios and media layout helpers for portrait galleries and Humor Lab.
abstract final class ResponsiveMedia {
  static const double portraitAspect = 3 / 4;
  static const double storyAspect = 9 / 16;
  static const double landscapeAspect = 16 / 9;

  static const double _minAspect = 0.45;
  static const double _maxAspect = 2.5;

  static double clampAspect(
    double? ratio, {
    required double fallback,
  }) {
    return (ratio ?? fallback).clamp(_minAspect, _maxAspect);
  }

  static double galleryMaxHeightFraction(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    if (height < ResponsiveBreakpoints.veryCompactHeight) {
      return 0.38;
    }
    if (height < ResponsiveBreakpoints.compactHeight) {
      return 0.45;
    }
    return 0.55;
  }

  static double galleryMaxHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height *
        galleryMaxHeightFraction(context);
  }

  static double mediaPlaceholderIcon(double frameHeight) {
    return (frameHeight * 0.22).clamp(48.0, 88.0);
  }
}
