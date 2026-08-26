import 'package:flutter/widgets.dart';

/// Supported UI languages. Mevora ships Turkish and English only.
enum AppLanguage {
  turkish('tr'),
  english('en');

  const AppLanguage(this.code);

  final String code;

  Locale get locale => Locale(code);

  static const AppLanguage fallback = AppLanguage.turkish;

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('tr'),
  ];

  static AppLanguage fromCode(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized == 'tr' || normalized.startsWith('tr_') || normalized.startsWith('tr-')) {
      return AppLanguage.turkish;
    }
    if (normalized == 'en' || normalized.startsWith('en_') || normalized.startsWith('en-')) {
      return AppLanguage.english;
    }
    return AppLanguage.fallback;
  }

  /// First launch / no saved preference: Turkish device → TR, English device → EN,
  /// anything else → TR (Mevora is a Turkish-first app).
  static AppLanguage fromDeviceLocale(Locale locale) {
    if (locale.languageCode.toLowerCase() == 'tr') {
      return AppLanguage.turkish;
    }
    if (locale.languageCode.toLowerCase() == 'en') {
      return AppLanguage.english;
    }
    return AppLanguage.turkish;
  }
}
