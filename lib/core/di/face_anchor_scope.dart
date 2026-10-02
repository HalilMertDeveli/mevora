import 'package:flutter/widgets.dart';
import 'package:mevora/core/di/face_anchor_services_factory.dart';

class FaceAnchorScope extends InheritedWidget {
  const FaceAnchorScope({
    super.key,
    required this.services,
    required super.child,
  });

  final FaceAnchorServices services;

  static FaceAnchorServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FaceAnchorScope>();
    assert(scope != null, 'FaceAnchorScope not found');
    return scope!.services;
  }

  /// Null where verification is not wired in (some tests, previews). Screens
  /// then simply do not offer it.
  static FaceAnchorServices? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FaceAnchorScope>()
        ?.services;
  }

  @override
  bool updateShouldNotify(FaceAnchorScope oldWidget) {
    return services != oldWidget.services;
  }
}
