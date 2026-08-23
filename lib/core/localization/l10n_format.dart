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
    final current = (now ?? DateTime.now()).toLocal();
    final instant = value.toLocal();
    var delta = current.difference(instant);
    if (delta.isNegative) {
      assert(() {
        debugPrint(
          'L10nFormat.compactDate: future timestamp $instant (now $current)',
        );
        return true;
      }());
      delta = Duration.zero;
    }
    if (delta.inSeconds < 45) {
      return l10n.timeNow;
    }
    if (delta.inMinutes < 60) {
      final minutes = delta.inMinutes == 0 ? 1 : delta.inMinutes;
      return l10n.timeMinutes(minutes);
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

  static String lastSeen(AppLocalizations l10n, DateTime value, {DateTime? now}) {
    final local = value.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final time = DateFormat.jm(l10n.localeName).format(local);
    if (_isSameDay(local, current)) {
      return l10n.lastSeenToday(time);
    }
    final yesterday = current.subtract(const Duration(days: 1));
    if (_isSameDay(local, yesterday)) {
      return l10n.lastSeenYesterday(time);
    }
    final date = DateFormat.MMMd(l10n.localeName).format(local);
    return l10n.lastSeenOnDate(date, time);
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
