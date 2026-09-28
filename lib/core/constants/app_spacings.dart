/// Spacing scale (4-pt). Named steps cover almost everything; the `sN`
/// steps are the in-betweens the named ones skip.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double s12 = 12;
  static const double md = 16;
  static const double s20 = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double s40 = 40;
  static const double xxl = 48;

  /// Horizontal page gutter.
  static const double screenPadding = 20;
  static const double cardPadding = 20;

  /// Minimum interactive size (Material / WCAG 2.5.5 target size).
  static const double minTouchTarget = 48;
}
