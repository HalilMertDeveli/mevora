import 'package:firebase_analytics/firebase_analytics.dart';

/// Product analytics for phone auth. Events never include phone, OTP, or tokens.
abstract class AuthAnalytics {
  Future<void> phoneAuthStarted();
  Future<void> otpSent();
  Future<void> otpVerified();
  Future<void> phoneAuthFailed();
  Future<void> otpResend();
  Future<void> otpVerificationFailed();
}

class NoOpAuthAnalytics implements AuthAnalytics {
  const NoOpAuthAnalytics();

  @override
  Future<void> phoneAuthStarted() async {}

  @override
  Future<void> otpSent() async {}

  @override
  Future<void> otpVerified() async {}

  @override
  Future<void> phoneAuthFailed() async {}

  @override
  Future<void> otpResend() async {}

  @override
  Future<void> otpVerificationFailed() async {}
}

class FirebaseAuthAnalytics implements AuthAnalytics {
  FirebaseAuthAnalytics({FirebaseAnalytics? analytics})
    : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  Future<void> _log(String name) {
    return _analytics.logEvent(name: name);
  }

  @override
  Future<void> phoneAuthStarted() => _log('phone_auth_started');

  @override
  Future<void> otpSent() => _log('otp_sent');

  @override
  Future<void> otpVerified() => _log('otp_verified');

  @override
  Future<void> phoneAuthFailed() => _log('phone_auth_failed');

  @override
  Future<void> otpResend() => _log('otp_resend');

  @override
  Future<void> otpVerificationFailed() => _log('otp_verification_failed');
}
