import 'package:flutter/material.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/services/app_logger.dart';

extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);

  ColorScheme get colors => theme.colorScheme;

  TextTheme get textTheme => theme.textTheme;

  AppConfig get config => AppScope.of(this).config;

  AppLogger get logger => AppScope.of(this).logger;

  bool get isDark => theme.brightness == Brightness.dark;
}
