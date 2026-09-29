import 'package:mevora/features/authentication/domain/auth_messages.dart';

/// OTP helpers used by the phone verification flow and unit tests.
abstract final class OtpValidator {
  static const int length = 6;

  /// One two-minute window drives both the resend cooldown and how long the
  /// Android SDK keeps listening for the SMS (`verifyPhoneNumber` timeout).
  /// Two minutes is the SDK's maximum. It is not the OTP's server-side
  /// lifetime — Firebase decides that — so nothing expires the code early.
  static const int resendSeconds = 120;
  static const Duration autoRetrievalTimeout = Duration(
    seconds: resendSeconds,
  );
  static const int maxResendAttempts = 3;

  static bool isComplete(String code) => RegExp(r'^\d{6}$').hasMatch(code);

  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'\D'), '');

  static String? validate(String code) {
    final digits = digitsOnly(code);
    if (digits.isEmpty) {
      return AuthMessages.invalidOtp;
    }
    if (digits.length != length || !isComplete(digits)) {
      return AuthMessages.invalidOtp;
    }
    return null;
  }
}
