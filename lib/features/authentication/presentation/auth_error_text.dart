import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/features/authentication/domain/entities/phone_auth_state.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';

String? localizeAuthError(AppLocalizations l10n, AuthController auth) {
  final kind = auth.errorKind;
  if (kind != null) {
    return L10nErrors.auth(l10n, kind);
  }
  return auth.errorMessage;
}

String? localizePhoneError(AppLocalizations l10n, PhoneAuthState state) {
  final AuthErrorKind? kind = switch (state) {
    PhoneNumberEntering(:final kind) => kind,
    OtpError(:final kind) => kind,
    SmsSendError(:final kind) => kind,
    TooManyAttempts(:final kind) => kind,
    _ => null,
  };
  final firebaseCode = switch (state) {
    PhoneNumberEntering(:final firebaseCode) => firebaseCode,
    OtpError(:final firebaseCode) => firebaseCode,
    SmsSendError(:final firebaseCode) => firebaseCode,
    TooManyAttempts(:final firebaseCode) => firebaseCode,
    _ => null,
  };
  final localized = kind != null
      ? L10nErrors.auth(l10n, kind)
      : switch (state) {
          PhoneNumberEntering(:final message) => message,
          OtpSent(:final message) => message,
          OtpError(:final message) => message,
          SmsSendError(:final message) => message,
          TooManyAttempts(:final message) => message,
          _ => null,
        };
  if (localized == null) {
    return null;
  }
  // Development / debug builds surface the Firebase code so failures are
  // diagnosable. Production keeps the localized message only.
  if (kDebugMode && firebaseCode != null && firebaseCode.isNotEmpty) {
    return '$localized\nFirebase: $firebaseCode';
  }
  return localized;
}
