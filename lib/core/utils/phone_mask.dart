/// Phone number helpers. Masking never exposes the full number in OTP UI.
abstract final class PhoneMask {
  static String e164(String dialCode, String nationalNumber) {
    var digits = nationalNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+$dialCode$digits';
  }

  static bool isValidE164(String value) {
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim());
  }

  /// Example: +9053XXXXXX42 → +90 5•• ••• •• 42
  static String mask(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      return e164;
    }

    final countryLength = _countryCodeLength(digits);
    final country = digits.substring(0, countryLength);
    final national = digits.substring(countryLength);
    if (national.length < 4) {
      return '+$country ••••••';
    }

    final first = national.substring(0, 1);
    final lastTwo = national.substring(national.length - 2);
    return '+$country $first•• ••• •• $lastTwo';
  }

  static int _countryCodeLength(String digits) {
    if (digits.startsWith('1') ||
        digits.startsWith('7') ||
        digits.startsWith('20') ||
        digits.startsWith('27') ||
        digits.startsWith('30') ||
        digits.startsWith('31') ||
        digits.startsWith('32') ||
        digits.startsWith('33') ||
        digits.startsWith('34') ||
        digits.startsWith('36') ||
        digits.startsWith('39') ||
        digits.startsWith('40') ||
        digits.startsWith('41') ||
        digits.startsWith('43') ||
        digits.startsWith('44') ||
        digits.startsWith('45') ||
        digits.startsWith('46') ||
        digits.startsWith('47') ||
        digits.startsWith('48') ||
        digits.startsWith('49') ||
        digits.startsWith('51') ||
        digits.startsWith('52') ||
        digits.startsWith('53') ||
        digits.startsWith('54') ||
        digits.startsWith('55') ||
        digits.startsWith('56') ||
        digits.startsWith('57') ||
        digits.startsWith('58') ||
        digits.startsWith('60') ||
        digits.startsWith('61') ||
        digits.startsWith('62') ||
        digits.startsWith('63') ||
        digits.startsWith('64') ||
        digits.startsWith('65') ||
        digits.startsWith('66') ||
        digits.startsWith('81') ||
        digits.startsWith('82') ||
        digits.startsWith('84') ||
        digits.startsWith('86') ||
        digits.startsWith('90') ||
        digits.startsWith('91') ||
        digits.startsWith('92') ||
        digits.startsWith('93') ||
        digits.startsWith('94') ||
        digits.startsWith('95') ||
        digits.startsWith('98')) {
      if (digits.startsWith('1') || digits.startsWith('7')) {
        return 1;
      }
      return 2;
    }
    return digits.length >= 3 ? 3 : 2;
  }
}
