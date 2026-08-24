import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/utils/otp_validator.dart';
import 'package:mevora/features/authentication/data/services/auth_analytics.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/country_code.dart';
import 'package:mevora/features/authentication/domain/entities/phone_auth_state.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/repositories/auth_repository.dart';
import 'package:mevora/features/authentication/domain/services/e164_formatter.dart';
import 'package:mevora/features/authentication/domain/services/phone_number_validator.dart';
import 'package:mevora/features/authentication/domain/usecases/auth_usecases.dart';

/// Presentation controller for phone + SMS OTP. Never stores the OTP.
class PhoneAuthController extends ChangeNotifier {
  PhoneAuthController({
    required SendPhoneVerificationCode sendPhoneVerificationCode,
    required VerifyPhoneCode verifyPhoneCode,
    required ResendPhoneVerificationCode resendPhoneVerificationCode,
    required AuthRepository authRepository,
    required AppLogger logger,
    AuthAnalytics? analytics,
  }) : _send = sendPhoneVerificationCode,
       _verify = verifyPhoneCode,
       _resend = resendPhoneVerificationCode,
       _authRepository = authRepository,
       _logger = logger,
       _analytics = analytics ?? const NoOpAuthAnalytics();

  final SendPhoneVerificationCode _send;
  final VerifyPhoneCode _verify;
  final ResendPhoneVerificationCode _resend;
  final AuthRepository _authRepository;
  final AppLogger _logger;
  final AuthAnalytics _analytics;

  PhoneAuthState _state = const PhoneNumberEntering();
  CountryCode _country = CountryCodes.turkey;
  String _nationalNumber = '';
  int _resendSeconds = 0;
  Timer? _timer;

  PhoneAuthState get state => _state;
  CountryCode get country => _country;
  String get nationalNumber => _nationalNumber;
  int get resendSeconds => _resendSeconds;
  bool get hasActiveChallenge => _challengeOf(_state) != null;
  bool get canResend =>
      _resendSeconds == 0 && hasActiveChallenge && !_isBusy;
  bool get _isBusy => _state is SendingOtp || _state is VerifyingOtp;

  String get formattedNational =>
      E164Formatter.formatNational(_country, _nationalNumber);

  void selectCountry(CountryCode country) {
    _country = country;
    notifyListeners();
  }

  void updateNationalNumber(String value) {
    _nationalNumber = E164Formatter.digitsOnly(value);
    if (_state is SmsSendError || _state is PhoneNumberEntering) {
      _state = const PhoneNumberEntering();
    }
    notifyListeners();
  }

  Future<bool> sendCode() async {
    if (_isBusy) {
      return false;
    }
    final validation = PhoneNumberValidator.validate(
      country: _country,
      nationalNumber: _nationalNumber,
    );
    if (!validation.isValid) {
      _state = PhoneNumberEntering(
        message: validation.message,
        kind: AuthErrorKind.invalidPhone,
      );
      notifyListeners();
      return false;
    }

    _state = const SendingOtp();
    notifyListeners();
    await _analytics.phoneAuthStarted();
    // ignore: avoid_print
    print('[PHONE_AUTH] START controller-send');
    _logger.info('phone_auth send requested');

    final result = await _send(validation.e164!);
    switch (result) {
      case Success<PhoneChallenge>(:final value):
        // ignore: avoid_print
        print(
          '[PHONE_AUTH] CODE_SENT controller verificationIdEmpty=${value.verificationId.isEmpty} auto=${value.autoVerified}',
        );
        if (value.autoVerified) {
          final auto = await _authRepository.completePhoneAutoVerification();
          switch (auto) {
            case Success<AuthUser>(:final value):
              // ignore: avoid_print
              print('[PHONE_AUTH] SIGN_IN_SUCCESS controller-auto');
              _state = PhoneAuthenticated(value);
              await _analytics.otpVerified();
              notifyListeners();
              return true;
            case Err<AuthUser>(:final failure):
              return _failSend(failure);
          }
        }
        _state = OtpSent(challenge: value);
        _startCooldown();
        await _analytics.otpSent();
        // ignore: avoid_print
        print('[PHONE_AUTH] NAVIGATION otp-screen');
        notifyListeners();
        return true;
      case Err<PhoneChallenge>(:final failure):
        return _failSend(failure);
    }
  }

  Future<bool> verify(String smsCode) async {
    if (_isBusy) {
      return false;
    }
    final challenge = _challengeOf(_state);
    if (challenge == null || challenge.verificationId.isEmpty) {
      _state = const PhoneNumberEntering(kind: AuthErrorKind.sessionExpired);
      notifyListeners();
      return false;
    }
    final otpError = OtpValidator.validate(smsCode);
    if (otpError != null) {
      _state = OtpError(
        challenge: challenge,
        message: otpError,
        kind: AuthErrorKind.invalidOtp,
      );
      notifyListeners();
      return false;
    }

    _state = VerifyingOtp(challenge: challenge);
    notifyListeners();

    final result = await _verify(challenge: challenge, smsCode: smsCode);
    switch (result) {
      case Success<AuthUser>(:final value):
        _timer?.cancel();
        // ignore: avoid_print
        print('[PHONE_AUTH] SIGN_IN_SUCCESS controller-manual');
        // ignore: avoid_print
        print('[PHONE_AUTH] FIREBASE_UID_RECEIVED controller');
        _state = PhoneAuthenticated(value);
        await _analytics.otpVerified();
        // ignore: avoid_print
        print('[PHONE_AUTH] NAVIGATION after-auth');
        notifyListeners();
        return true;
      case Err<AuthUser>(:final failure):
        await _analytics.otpVerificationFailed();
        final code = failure is AuthFailure ? failure.code : null;
        // ignore: avoid_print
        print('[PHONE_AUTH] VERIFICATION_FAILED otp code=$code message=${failure.message}');
        if (_isTooMany(failure)) {
          _state = TooManyAttempts(
            failure.message,
            kind: failure is AuthFailure ? failure.kind : AuthErrorKind.tooManyAttempts,
            firebaseCode: code,
          );
        } else {
          _state = OtpError(
            challenge: challenge,
            message: failure.message,
            kind: failure is AuthFailure ? failure.kind : AuthErrorKind.invalidOtp,
            firebaseCode: code,
          );
        }
        notifyListeners();
        return false;
    }
  }

  Future<bool> resend() async {
    final challenge = _challengeOf(_state);
    if (challenge == null || !canResend) {
      return false;
    }
    _state = const SendingOtp();
    notifyListeners();
    final result = await _resend(challenge);
    switch (result) {
      case Success<PhoneChallenge>(:final value):
        _state = OtpSent(challenge: value);
        _startCooldown();
        await _analytics.otpResend();
        notifyListeners();
        return true;
      case Err<PhoneChallenge>(:final failure):
        await _analytics.phoneAuthFailed();
        return _failSend(failure);
    }
  }

  void restoreOrReset() {
    final challenge = _challengeOf(_state);
    if (challenge == null || challenge.verificationId.isEmpty) {
      resetToPhoneEntry();
    }
  }

  void resetToPhoneEntry() {
    _timer?.cancel();
    _resendSeconds = 0;
    _state = const PhoneNumberEntering();
    notifyListeners();
  }

  bool _failSend(Failure failure) {
    final kind = failure is AuthFailure ? failure.kind : AuthErrorKind.smsFailed;
    final code = failure is AuthFailure ? failure.code : null;
    // ignore: avoid_print
    print('[PHONE_AUTH] VERIFICATION_FAILED send code=$code kind=$kind message=${failure.message}');
    _logger.warning(
      'phone_auth send failed kind=$kind code=$code',
      error: failure.message,
    );
    unawaited(_analytics.phoneAuthFailed());
    _state = _isTooMany(failure)
        ? TooManyAttempts(
            failure.message,
            kind: kind == AuthErrorKind.smsQuota
                ? AuthErrorKind.smsQuota
                : AuthErrorKind.tooManyAttempts,
            firebaseCode: code,
          )
        : SmsSendError(
            failure.message,
            kind: kind,
            firebaseCode: code,
          );
    notifyListeners();
    return false;
  }

  bool _isTooMany(Failure failure) {
    return failure is AuthFailure &&
        (failure.kind == AuthErrorKind.tooManyAttempts ||
            failure.kind == AuthErrorKind.smsQuota);
  }

  PhoneChallenge? _challengeOf(PhoneAuthState state) {
    return switch (state) {
      OtpSent(:final challenge) => challenge,
      VerifyingOtp(:final challenge) => challenge,
      OtpError(:final challenge) => challenge,
      _ => null,
    };
  }

  void _startCooldown() {
    _timer?.cancel();
    _resendSeconds = OtpValidator.resendSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds <= 1) {
        timer.cancel();
        _resendSeconds = 0;
      } else {
        _resendSeconds -= 1;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
