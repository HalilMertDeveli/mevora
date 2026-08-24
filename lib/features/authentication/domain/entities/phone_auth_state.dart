import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';

/// Phone-auth UI states. OTP values are never stored on these objects.
sealed class PhoneAuthState {
  const PhoneAuthState();
}

final class PhoneNumberEntering extends PhoneAuthState {
  const PhoneNumberEntering({this.message, this.kind, this.firebaseCode});

  final String? message;
  final AuthErrorKind? kind;
  final String? firebaseCode;
}

final class SendingOtp extends PhoneAuthState {
  const SendingOtp();
}

final class OtpSent extends PhoneAuthState {
  const OtpSent({required this.challenge, this.message});

  final PhoneChallenge challenge;
  final String? message;
}

final class VerifyingOtp extends PhoneAuthState {
  const VerifyingOtp({required this.challenge});

  final PhoneChallenge challenge;
}

final class PhoneAuthenticated extends PhoneAuthState {
  const PhoneAuthenticated(this.user);

  final AuthUser user;
}

final class OtpError extends PhoneAuthState {
  const OtpError({
    required this.challenge,
    required this.message,
    this.kind,
    this.firebaseCode,
  });

  final PhoneChallenge challenge;
  final String message;
  final AuthErrorKind? kind;
  final String? firebaseCode;
}

final class SmsSendError extends PhoneAuthState {
  const SmsSendError(this.message, {this.kind, this.firebaseCode});

  final String message;
  final AuthErrorKind? kind;
  final String? firebaseCode;
}

final class TooManyAttempts extends PhoneAuthState {
  const TooManyAttempts(this.message, {this.kind, this.firebaseCode});

  final String message;
  final AuthErrorKind? kind;
  final String? firebaseCode;
}
