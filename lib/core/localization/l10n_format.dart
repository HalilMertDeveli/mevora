import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Locale-aware formatting. The database stores UTC timestamps, never display strings.
abstract final class L10nFormat {
  static String distance(AppLocalizations l10n, double kilometers) {
    if (kilometers < 1) {
      return l10n.distanceLessThanOne;
    }
    if (kilometers >= 100) {
      return l10n.distanceFar;
    }
    return l10n.distanceAway(_distanceNumber(l10n.localeName, kilometers));
  }

  static String distanceFromKm(Locale locale, double kilometers) {
    final l10n = lookupAppLocalizations(locale);
    return distance(l10n, kilometers);
  }

  static String _distanceNumber(String localeName, double kilometers) {
    final rounded = kilometers.roundToDouble();
    if ((kilometers - rounded).abs() < 0.05) {
      return NumberFormat.decimalPattern(localeName).format(kilometers.round());
    }
    return NumberFormat('#.#', localeName).format(kilometers);
  }

  static String compactDate(AppLocalizations l10n, DateTime? value, {DateTime? now}) {
    if (value == null) {
      return '';
    }
    final current = now ?? DateTime.now();
    final delta = current.difference(value);
    if (delta.inSeconds < 45) {
      return l10n.timeNow;
    }
    if (delta.inMinutes < 60) {
      return l10n.timeMinutes(delta.inMinutes);
    }
    if (delta.inHours < 24) {
      return l10n.timeHours(delta.inHours);
    }
    if (delta.inDays < 7) {
      return l10n.timeDays(delta.inDays);
    }
    return DateFormat.MMMd(l10n.localeName).format(value.toLocal());
  }

  static String mediumDate(AppLocalizations l10n, DateTime value) {
    return DateFormat.yMMMd(l10n.localeName).format(value.toLocal());
  }
}
