import 'package:flutter/widgets.dart';
import 'package:mevora/core/localization/language_controller.dart';

/// Injects [LanguageController]. Widgets never resolve device locale themselves.
class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({
    super.key,
    required LanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static LanguageController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    assert(scope != null, 'LanguageScope not found in the widget tree');
    return scope!.notifier!;
  }

  static LanguageController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier;
  }
}
