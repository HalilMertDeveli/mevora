import 'package:flutter/widgets.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/services/app_logger.dart';

/// Provides process-wide dependencies without a state-management package.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.config,
    required this.logger,
    required super.child,
  });

  final AppConfig config;
  final AppLogger logger;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  static AppScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScope>();
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return config != oldWidget.config || logger != oldWidget.logger;
  }
}
