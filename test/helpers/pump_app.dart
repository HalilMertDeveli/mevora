import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_theme.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Scaffold(body: child),
  );
}
