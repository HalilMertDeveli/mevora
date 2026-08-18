import 'package:mevora/core/utils/phone_mask.dart';
import 'package:mevora/features/authentication/domain/entities/country_code.dart';

/// Formats national numbers into E.164 and display groups.
abstract final class E164Formatter {
  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'\D'), '');

  /// Trunk `0` and an accidental country dial prefix are stripped so the
  /// national length check matches what Firebase Phone Auth expects.
  static String normalizedNationalDigits(
    CountryCode country,
    String nationalNumber,
  ) {
    var digits = digitsOnly(nationalNumber);
    final dial = country.dialCode;
    if (digits.startsWith(dial) &&
        digits.length - dial.length >= country.minNationalLength) {
      digits = digits.substring(dial.length);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  static String toE164(CountryCode country, String nationalNumber) {
    return '+${country.dialCode}${normalizedNationalDigits(country, nationalNumber)}';
  }

  static bool isValidE164(String value) => PhoneMask.isValidE164(value);

  static String mask(String e164) => PhoneMask.mask(e164);

  static String formatNational(CountryCode country, String input) {
    final digits = digitsOnly(input);
    final groups = _groupsFor(country);
    final buffer = StringBuffer();
    var index = 0;
    for (final size in groups) {
      if (index >= digits.length) {
        break;
      }
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      final end = (index + size).clamp(0, digits.length);
      buffer.write(digits.substring(index, end));
      index = end;
    }
    if (index < digits.length) {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(digits.substring(index));
    }
    return buffer.toString();
  }

  static List<int> _groupsFor(CountryCode country) {
    return switch (country.isoCode) {
      'TR' => const [3, 3, 2, 2],
      'US' || 'CA' => const [3, 3, 4],
      'GB' => const [4, 3, 3],
      'DE' => const [3, 4, 4],
      'FR' => const [1, 2, 2, 2, 2],
      _ => const [3, 3, 3, 3],
    };
  }
}
