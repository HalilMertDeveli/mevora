import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_durations.dart';

/// Short fade + slight horizontal slide. No full-screen overlay, no Rive veil.
abstract final class MevoraPageTransitions {
  static CustomTransitionPage<T> fadeSlide<T>({
    required LocalKey key,
    required Widget child,
    bool cover = false,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: AppDurations.page,
      reverseTransitionDuration: AppDurations.page,
      transitionsBuilder: build,
    );
  }

  /// Same motion for [Navigator.push] (non-go_router pages).
  static PageRoute<T> route<T extends Object?>({
    required WidgetBuilder builder,
    bool cover = false,
  }) {
    return PageRouteBuilder<T>(
      transitionDuration: AppDurations.page,
      reverseTransitionDuration: AppDurations.page,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: build,
    );
  }

  static Widget build(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    final incoming = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.88).animate(outgoing),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.035, 0),
        ).animate(outgoing),
        child: FadeTransition(
          opacity: incoming,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(incoming),
            child: child,
          ),
        ),
      ),
    );
  }
}
