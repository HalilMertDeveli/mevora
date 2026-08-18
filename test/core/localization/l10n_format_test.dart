import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tr = lookupAppLocalizations(const Locale('tr'));

  test('invalid OTP is localized for EN and TR', () {
    expect(L10nErrors.auth(en, AuthErrorKind.invalidOtp), 'Invalid verification code.');
    expect(L10nErrors.auth(tr, AuthErrorKind.invalidOtp), 'Doğrulama kodu geçersiz.');
  });

  test('distance uses locale decimal separators and dating copy', () {
    expect(L10nFormat.distance(en, 2), '2 km away');
    expect(L10nFormat.distance(tr, 2), '2 km uzakta');
    expect(L10nFormat.distance(en, 2.5), '2.5 km away');
    expect(L10nFormat.distance(tr, 2.5), '2,5 km uzakta');
    expect(L10nFormat.distance(en, 0.4), 'Less than 1 km away');
    expect(L10nFormat.distance(tr, 0.4), "1 km'den yakın");
  });

  test('unsupported device locale falls back to English before lookup', () {
    final locale = AppLanguage.fromDeviceLocale(const Locale('de')).locale;
    expect(lookupAppLocalizations(locale).signIn, en.signIn);
    expect(
      () => lookupAppLocalizations(const Locale('de')),
      throwsA(isA<FlutterError>()),
    );
  });

  test('long EN and TR boost strings stay defined', () {
    expect(en.boostSubtitle.length, greaterThan(20));
    expect(tr.boostSubtitle.length, greaterThan(20));
  });
}
