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

  test('billing-not-enabled is localized for EN and TR', () {
    expect(
      L10nErrors.auth(en, AuthErrorKind.billingNotEnabled),
      'Firebase billing (Blaze) is required to send SMS verification codes.',
    );
    expect(
      L10nErrors.auth(tr, AuthErrorKind.billingNotEnabled),
      'SMS gönderimi için Firebase faturalandırması (Blaze) gerekli.',
    );
  });

  test('app verification is localized for EN and TR', () {
    expect(
      L10nErrors.auth(en, AuthErrorKind.appVerification),
      en.authAppVerification,
    );
    expect(
      L10nErrors.auth(tr, AuthErrorKind.appVerification),
      tr.authAppVerification,
    );
  });

  test('email-in-use is localized for EN and TR', () {
    expect(
      L10nErrors.auth(en, AuthErrorKind.emailInUse),
      'An account already exists for that email.',
    );
    expect(
      L10nErrors.auth(tr, AuthErrorKind.emailInUse),
      'Bu e-posta ile zaten bir hesap var.',
    );
  });

  test('distance uses locale decimal separators and dating copy', () {
    expect(L10nFormat.distance(en, 2), '2 km away');
    expect(L10nFormat.distance(tr, 2), '2 km uzakta');
    expect(L10nFormat.distance(en, 2.5), '2.5 km away');
    expect(L10nFormat.distance(tr, 2.5), '2,5 km uzakta');
    expect(L10nFormat.distance(en, 0.4), 'Less than 1 km away');
    expect(L10nFormat.distance(tr, 0.4), "1 km'den yakın");
  });

  test('unsupported device locale falls back to Turkish before lookup', () {
    final locale = AppLanguage.fromDeviceLocale(const Locale('de')).locale;
    expect(lookupAppLocalizations(locale).signIn, tr.signIn);
    expect(
      () => lookupAppLocalizations(const Locale('de')),
      throwsA(isA<FlutterError>()),
    );
  });

  test('Google Sign-In localization keys exist for EN and TR', () {
    expect(en.continueWithGoogle, isNotEmpty);
    expect(tr.continueWithGoogle, isNotEmpty);
    expect(en.signingIn, 'Signing in...');
    expect(tr.signingIn, 'Giriş yapılıyor...');
    expect(en.googleSignInCancelled, isNotEmpty);
    expect(tr.googleSignInCancelled, isNotEmpty);
    expect(en.googleSignInFailed, isNotEmpty);
    expect(tr.googleSignInFailed, isNotEmpty);
    expect(en.authNetwork, isNotEmpty);
    expect(tr.authNetwork, isNotEmpty);
    expect(en.tryAgain, isNotEmpty);
    expect(tr.tryAgain, isNotEmpty);
    expect(L10nErrors.auth(en, AuthErrorKind.oauth), en.authGoogleFailed);
    expect(L10nErrors.auth(tr, AuthErrorKind.cancelled), tr.authCancelled);
    expect(L10nErrors.auth(en, AuthErrorKind.network), en.authNetwork);
  });
}
