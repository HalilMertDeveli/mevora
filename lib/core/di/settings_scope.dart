import 'package:flutter/material.dart';
import 'package:mevora/core/di/settings_services_factory.dart';

class SettingsScope extends InheritedWidget {
  const SettingsScope({
    super.key,
    required this.services,
    required super.child,
  });

  final SettingsServices services;

  static SettingsServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope not found');
    return scope!.services;
  }

  static SettingsServices? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.services;
  }

  @override
  bool updateShouldNotify(SettingsScope oldWidget) =>
      oldWidget.services != services;
}
