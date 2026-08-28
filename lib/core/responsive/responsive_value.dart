import 'package:flutter/material.dart';

/// Clamps and fraction helpers shared across responsive surfaces.
abstract final class ResponsiveValue {
  static double clamp(
    double value, {
    required double min,
    required double max,
  }) {
    return value.clamp(min, max);
  }

  static double heightFraction(
    BuildContext context,
    double fraction, {
    double? max,
  }) {
    final height = MediaQuery.sizeOf(context).height * fraction;
    if (max != null) {
      return height.clamp(0, max);
    }
    return height;
  }

  static double widthFraction(BuildContext context, double fraction) {
    return MediaQuery.sizeOf(context).width * fraction;
  }
}
