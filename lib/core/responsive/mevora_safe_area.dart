import 'package:flutter/material.dart';

import 'package:mevora/core/constants/app_spacings.dart';

/// Safe-area helpers for sheets, overlays, and keyboard-aware chrome.
abstract final class MevoraSafeAreaInsets {
  static double top(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).top;
  }

  static double bottom(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return viewInsets.bottom > 0 ? viewInsets.bottom : viewPadding.bottom;
  }

  static double systemBottom(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).bottom;
  }

  static EdgeInsets sheetOuterPadding(BuildContext context) {
    final bottomInset = bottom(context);
    return EdgeInsets.only(
      bottom: bottomInset > 0 ? bottomInset : AppSpacing.sm,
    );
  }
}
