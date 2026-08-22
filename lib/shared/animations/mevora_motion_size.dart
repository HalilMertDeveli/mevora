import 'package:flutter/material.dart';

/// Responsive caps so Rive accents stay small on every phone size.
abstract final class MevoraMotionSize {
  /// Tiny inline spinner / badge (chat, buttons, sync rows).
  static double inline(BuildContext context) {
    return _scale(context, preferred: 40, min: 32, max: 48);
  }

  /// Page / section loading accent (never near full-bleed).
  static double loading(BuildContext context) {
    return _scale(context, preferred: 52, min: 40, max: 64);
  }

  /// Empty / status illustrations.
  static double accent(BuildContext context) {
    return _scale(context, preferred: 72, min: 56, max: 88);
  }

  /// Match / celebration header only.
  static double celebration(BuildContext context) {
    return _scale(context, preferred: 88, min: 64, max: 104);
  }

  /// Tab / route micro-accent during transitions.
  static double transition(BuildContext context) {
    return _scale(context, preferred: 48, min: 40, max: 56);
  }

  static double _scale(
    BuildContext context, {
    required double preferred,
    required double min,
    required double max,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final factor = (width / 390).clamp(0.85, 1.12);
    return (preferred * factor).clamp(min, max);
  }
}
