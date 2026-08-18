import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/l10n/app_localizations.dart';

Widget wrapWithApp(
  Widget child, {
  Locale locale = const Locale('en'),
  bool scaffold = true,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: scaffold ? Scaffold(body: child) : child,
  );
}
