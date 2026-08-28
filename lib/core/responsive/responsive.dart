import 'package:flutter/material.dart';

import 'package:mevora/core/responsive/responsive_breakpoints.dart';
import 'package:mevora/core/responsive/responsive_spacing.dart';

export 'package:mevora/core/responsive/mevora_safe_area.dart';
export 'package:mevora/core/responsive/responsive_breakpoints.dart';
export 'package:mevora/core/responsive/responsive_media.dart';
export 'package:mevora/core/responsive/responsive_spacing.dart';
export 'package:mevora/core/responsive/responsive_value.dart';

extension ResponsiveContext on BuildContext {
  bool get isCompactHeight =>
      MediaQuery.sizeOf(this).height <
      ResponsiveBreakpoints.compactHeight;

  bool get isVeryCompactHeight =>
      MediaQuery.sizeOf(this).height <
      ResponsiveBreakpoints.veryCompactHeight;

  bool get isNarrowWidth =>
      MediaQuery.sizeOf(this).width < ResponsiveBreakpoints.narrowWidth;

  double get responsiveGutter => ResponsiveSpacing.horizontalGutter(this);
}
