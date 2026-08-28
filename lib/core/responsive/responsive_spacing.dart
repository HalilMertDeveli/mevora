import 'package:flutter/material.dart';

import 'package:mevora/core/responsive/responsive_value.dart';

/// Horizontal spacing derived from viewport width.
abstract final class ResponsiveSpacing {
  static double horizontalGutter(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return ResponsiveValue.clamp(width * 0.064, min: 16, max: 24);
  }
}
