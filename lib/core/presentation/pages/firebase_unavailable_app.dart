import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';

/// Full-screen fallback when Firebase cannot initialize.
///
/// Never shows raw SDK or network exception text.
class MevoraStartupErrorApp extends StatelessWidget {
  const MevoraStartupErrorApp({super.key, this.locale});

  /// Optional override used by tests. Production uses the device locale.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final resolved = AppLanguage.fromDeviceLocale(
      locale ?? PlatformDispatcher.instance.locale,
    ).locale;
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      locale: resolved,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: SafeArea(
              child: MevoraErrorView(
                title: l10n.somethingWentWrong,
                message: l10n.firebaseUnavailableMessage,
              ),
            ),
          );
        },
      ),
    );
  }
}
