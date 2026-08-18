import 'package:firebase_analytics/firebase_analytics.dart';

/// Product analytics for auth. Events never include phone, email, OTP, or tokens.
abstract class AuthAnalytics {
  Future<void> phoneAuthStarted();
  Future<void> otpSent();
  Future<void> otpVerified();
  Future<void> phoneAuthFailed();
  Future<void> otpResend();
  Future<void> otpVerificationFailed();

  Future<void> googleLoginStarted();
  Future<void> googleLoginSuccess();
  Future<void> googleLoginFailed();
  Future<void> googleLoginCancelled();
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

  @override
  Future<void> googleLoginStarted() async {}

  @override
  Future<void> googleLoginSuccess() async {}

  @override
  Future<void> googleLoginFailed() async {}

  @override
  Future<void> googleLoginCancelled() async {}
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

  @override
  Future<void> googleLoginStarted() => _log('google_login_started');

  @override
  Future<void> googleLoginSuccess() => _log('google_login_success');

  @override
  Future<void> googleLoginFailed() => _log('google_login_failed');

  @override
  Future<void> googleLoginCancelled() => _log('google_login_cancelled');
}
