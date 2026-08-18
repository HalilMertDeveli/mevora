import 'package:flutter/material.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/l10n/app_localizations.dart';

AppLocalizations l10nEn() => lookupAppLocalizations(const Locale('en'));

AppLocalizations l10nTr() => lookupAppLocalizations(const Locale('tr'));

Future<LanguageController> loadedLanguageController({
  String? savedCode,
  Locale deviceLocale = const Locale('en'),
}) async {
  final controller = LanguageController(
    repository: LanguageRepository(
      local: MemoryLanguageDataSource(languageCode: savedCode),
    ),
    deviceLocale: deviceLocale,
  );
  await controller.load();
  return controller;
}
