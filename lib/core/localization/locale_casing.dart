import 'dart:ui' show Locale;

/// Locale-aware text casing.
///
/// `String.toUpperCase()` is locale-independent in Dart: it follows the
/// Unicode default mapping, where `i` becomes `I`. Turkish has two distinct
/// letters — dotted `i`/`İ` and dotless `ı`/`I` — so the default mapping
/// renders `bildirimler` as `BILDIRIMLER` instead of `BİLDİRİMLER`.
///
/// Use this wherever user-visible text is uppercased for presentation.
abstract final class LocaleCasing {
  /// Dotted capital I (U+0130) — the Turkish uppercase of `i`.
  static const String _dottedCapitalI = 'İ';

  /// Dotless small i (U+0131) — the Turkish lowercase of `I`.
  static const String _dotlessSmallI = 'ı';

  static bool _isTurkish(Locale locale) =>
      locale.languageCode.toLowerCase() == 'tr';

  /// Uppercases [value] using the casing rules of [locale].
  static String upper(String value, Locale locale) {
    if (!_isTurkish(locale)) {
      return value.toUpperCase();
    }
    // Pin the two Turkish-specific mappings before the default pass so the
    // Unicode rules cannot fold them back together.
    return value
        .replaceAll('i', _dottedCapitalI)
        .replaceAll(_dotlessSmallI, 'I')
        .toUpperCase();
  }
}
