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
  if (kind != null) {
    return L10nErrors.auth(l10n, kind);
  }
  return switch (state) {
    PhoneNumberEntering(:final message) => message,
    OtpSent(:final message) => message,
    OtpError(:final message) => message,
    SmsSendError(:final message) => message,
    TooManyAttempts(:final message) => message,
    _ => null,
  };
}
