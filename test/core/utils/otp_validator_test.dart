import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/utils/otp_validator.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';

void main() {
  test('accepts a complete 6-digit code', () {
    expect(OtpValidator.isComplete('123456'), isTrue);
    expect(OtpValidator.validate('123456'), isNull);
  });

  test('rejects empty, short, and non-digit codes', () {
    expect(OtpValidator.validate(''), AuthMessages.invalidOtp);
    expect(OtpValidator.validate('12'), AuthMessages.invalidOtp);
    expect(OtpValidator.validate('12ab56'), AuthMessages.invalidOtp);
    expect(OtpValidator.digitsOnly('1 2 3-4'), '1234');
  });

  test('resend copy matches the OTP screen spec', () {
    expect(OtpValidator.resendSeconds, 120);
    expect(
      AuthMessages.resendCountdown(42),
      'Yeni kodu 42 saniye sonra tekrar gönderebilirsin.',
    );
  });

  test('verification window is the 2-minute SDK maximum, shared by resend', () {
    // firebase_auth: "Maximum allowed value is 2 minutes" for the
    // verifyPhoneNumber auto-retrieval timeout.
    expect(OtpValidator.autoRetrievalTimeout, const Duration(minutes: 2));
    expect(
      OtpValidator.autoRetrievalTimeout.inSeconds,
      OtpValidator.resendSeconds,
    );
  });
}
