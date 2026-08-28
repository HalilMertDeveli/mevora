import 'package:flutter/widgets.dart';
import 'package:mevora/features/compatibility/domain/repositories/why_you_matched_repository.dart';

class CompatibilityScope extends InheritedWidget {
  const CompatibilityScope({
    super.key,
    required this.whyYouMatchedRepository,
    required super.child,
  });

  final WhyYouMatchedRepository whyYouMatchedRepository;

  static WhyYouMatchedRepository of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CompatibilityScope>();
    assert(scope != null, 'CompatibilityScope not found');
    return scope!.whyYouMatchedRepository;
  }

  static WhyYouMatchedRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CompatibilityScope>()
        ?.whyYouMatchedRepository;
  }

  @override
  bool updateShouldNotify(CompatibilityScope oldWidget) {
    return whyYouMatchedRepository != oldWidget.whyYouMatchedRepository;
  }
}
