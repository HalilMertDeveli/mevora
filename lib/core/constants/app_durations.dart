import 'package:flutter/animation.dart';

/// Motion timings. Three base speeds carry almost everything; the named
/// durations below are the few moments that deserve their own timing.
///
/// Motion communicates state, hierarchy, feedback or completion — never
/// decoration. See docs/ui/DESIGN_SYSTEM.md, "Motion".
abstract final class AppDurations {
  /// Press feedback, toggles, colour changes.
  static const Duration fast = Duration(milliseconds: 150);

  /// Most transitions: expanding, cross-fading, sheets.
  static const Duration normal = Duration(milliseconds: 250);

  /// Large surfaces entering: pages, the match moment's first beat.
  static const Duration slow = Duration(milliseconds: 400);

  static const Duration instant = Duration(milliseconds: 80);
  static const Duration button = fast;
  static const Duration short = Duration(milliseconds: 180);
  static const Duration page = normal;
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration discoveryCard = Duration(milliseconds: 260);
  static const Duration photo = Duration(milliseconds: 220);
  static const Duration like = Duration(milliseconds: 280);
  static const Duration pass = Duration(milliseconds: 240);
  static const Duration long = slow;

  /// Compact tab/route accent — keep short so it never feels like a wait.
  static const Duration coverShrink = Duration(milliseconds: 320);

  /// The full match moment (two portraits converge, then the line draws).
  static const Duration match = Duration(milliseconds: 1400);

  /// Signature success / celebration marks.
  static const Duration celebrate = Duration(milliseconds: 900);
}

/// Easing. Things entering decelerate; things leaving accelerate; things that
/// change in place use the standard curve.
abstract final class AppCurves {
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// A soft overshoot for moments of delight (match, boost). Use sparingly.
  static const Curve emphasized = Curves.easeOutBack;
}
