/// OTP helpers used by the phone verification flow and unit tests.
abstract final class OtpValidator {
  static const int length = 6;
  static const int resendSeconds = 60;
  static const int maxResendAttempts = 3;

  static bool isComplete(String code) => RegExp(r'^\d{6}$').hasMatch(code);

  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'\D'), '');

  static String? validate(String code) {
    final digits = digitsOnly(code);
    if (digits.isEmpty) {
      return 'Doğrulama kodunu gir.';
    }
    if (digits.length != length || !isComplete(digits)) {
      return 'Doğrulama kodu geçersiz.';
    }
    return null;
  }
}
