import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Relative timestamps without exposing an exact last-seen clock.
/// Prefer [L10nFormat.compactDate] from widgets that already have l10n.
abstract final class RelativeTime {
  static String compact(
    DateTime? value, {
    DateTime? now,
    String languageCode = 'en',
  }) {
    final l10n = lookupAppLocalizations(
      AppLanguage.fromCode(languageCode).locale,
    );
    return L10nFormat.compactDate(l10n, value, now: now);
  }
}
