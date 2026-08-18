import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';

/// Soft fade when a photo source changes. No looping decoration.
class MevoraPhotoFade extends StatelessWidget {
  const MevoraPhotoFade({
    super.key,
    required this.child,
    required this.photoKey,
  });

  final Widget child;
  final Object photoKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDurations.photo,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey(photoKey), child: child),
    );
  }
}
