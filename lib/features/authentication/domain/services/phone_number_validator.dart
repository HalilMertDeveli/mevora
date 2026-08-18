import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/country_code.dart';
import 'package:mevora/features/authentication/domain/services/e164_formatter.dart';

enum PhoneValidationIssue {
  empty,
  invalidChars,
  invalidLength,
  invalidCountry,
  invalidE164,
}

class PhoneValidationResult {
  const PhoneValidationResult._({this.issue, this.e164});

  const PhoneValidationResult.valid(String e164) : this._(e164: e164);

  const PhoneValidationResult.invalid(PhoneValidationIssue issue)
    : this._(issue: issue);

  final PhoneValidationIssue? issue;
  final String? e164;

  bool get isValid => issue == null && e164 != null;

  String? get message {
    return switch (issue) {
      PhoneValidationIssue.empty ||
      PhoneValidationIssue.invalidChars ||
      PhoneValidationIssue.invalidLength ||
      PhoneValidationIssue.invalidCountry ||
      PhoneValidationIssue.invalidE164 => AuthMessages.invalidPhone,
      null => null,
    };
  }
}

/// Domain-only phone validation. Widgets must not reimplement these rules.
abstract final class PhoneNumberValidator {
  static PhoneValidationResult validate({
    required CountryCode country,
    required String nationalNumber,
    List<CountryCode> catalog = CountryCodes.all,
  }) {
    final known = catalog.any((item) => item.isoCode == country.isoCode);
    if (!known) {
      return const PhoneValidationResult.invalid(
        PhoneValidationIssue.invalidCountry,
      );
    }

    final trimmed = nationalNumber.trim();
    if (trimmed.isEmpty) {
      return const PhoneValidationResult.invalid(PhoneValidationIssue.empty);
    }

    if (RegExp(r'[^\d\s\-\(\)]').hasMatch(trimmed)) {
      return const PhoneValidationResult.invalid(
        PhoneValidationIssue.invalidChars,
      );
    }

    final digits = E164Formatter.normalizedNationalDigits(country, trimmed);
    if (digits.isEmpty) {
      return const PhoneValidationResult.invalid(
        PhoneValidationIssue.invalidChars,
      );
    }
    if (digits.length < country.minNationalLength ||
        digits.length > country.maxNationalLength) {
      return const PhoneValidationResult.invalid(
        PhoneValidationIssue.invalidLength,
      );
    }

    final e164 = E164Formatter.toE164(country, trimmed);
    if (!E164Formatter.isValidE164(e164)) {
      return const PhoneValidationResult.invalid(
        PhoneValidationIssue.invalidE164,
      );
    }

    return PhoneValidationResult.valid(e164);
  }
}
