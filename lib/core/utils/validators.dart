import 'package:mevora/l10n/app_localizations.dart';

abstract final class Validators {
  static String? requiredField(
    String? value, {
    String field = 'This field',
    AppLocalizations? l10n,
  }) {
    if (value == null || value.trim().isEmpty) {
      return l10n?.fieldRequired(field) ?? '$field is required';
    }
    return null;
  }

  static String? email(String? value, [AppLocalizations? l10n]) {
    if (value == null || value.trim().isEmpty) {
      return l10n?.emailRequired ?? 'Email is required';
    }
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return l10n?.emailInvalid ?? 'Enter a valid email';
    }
    return null;
  }

  static String? minLength(
    String? value,
    int min, {
    String field = 'This field',
    AppLocalizations? l10n,
  }) {
    final requiredError = requiredField(value, field: field, l10n: l10n);
    if (requiredError != null) {
      return requiredError;
    }
    if (value!.trim().length < min) {
      return l10n?.fieldMinLength(field, min) ??
          '$field must be at least $min characters';
    }
    return null;
  }

  static String? e164Phone(String? value, [AppLocalizations? l10n]) {
    if (value == null || value.trim().isEmpty) {
      return l10n?.phoneRequired ?? 'Phone is required';
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim())) {
      return l10n?.authInvalidPhone ?? 'Enter a valid phone number';
    }
    return null;
  }

  static String? password(String? value, [AppLocalizations? l10n]) {
    if (value == null || value.isEmpty) {
      return l10n?.passwordRequired ?? 'Password is required';
    }
    if (value.length < 8) {
      return l10n?.passwordMinLength(8) ??
          'Password must be at least 8 characters';
    }
    return null;
  }

  static String? confirmPassword(
    String? value,
    String password, [
    AppLocalizations? l10n,
  ]) {
    if (value == null || value.trim().isEmpty) {
      return l10n?.fieldRequired(l10n.confirmPassword) ??
          'Confirm password is required';
    }
    if (value != password) {
      return l10n?.passwordsDoNotMatch ?? 'Passwords do not match';
    }
    return null;
  }

  static String? otpCode(String? value, [AppLocalizations? l10n]) {
    if (value == null || value.trim().isEmpty) {
      return l10n?.codeRequired ?? 'Code is required';
    }
    if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return l10n?.otpInvalidFormat ?? 'Enter the 6-digit code';
    }
    return null;
  }
}
