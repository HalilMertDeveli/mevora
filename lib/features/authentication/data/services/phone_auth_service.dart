import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/utils/otp_validator.dart';
import 'package:mevora/core/utils/phone_mask.dart';
import 'package:mevora/features/authentication/data/datasources/firebase_auth_data_source.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';

/// Production Firebase Phone Authentication. The SMS OTP is created and
/// verified only by Firebase Auth — never generated or stored in the app.
class PhoneAuthService implements FirebaseAuthDataSource {
  PhoneAuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  int _sendCount = 0;
  PhoneAuthCredential? _autoCredential;

  @override
  Future<PhoneChallenge> sendCode(
    String e164Phone, {
    int? forceResendingToken,
    int resendAttempt = 0,
  }) async {
    if (!PhoneMask.isValidE164(e164Phone)) {
      throw const AuthException(
        AuthMessages.invalidPhone,
        kind: AuthErrorKind.invalidPhone,
      );
    }
    if (_sendCount >= OtpValidator.maxResendAttempts + 1) {
      throw const AuthException(
        AuthMessages.tooManyAttempts,
        kind: AuthErrorKind.tooManyAttempts,
      );
    }

    final completer = Completer<PhoneChallenge>();

    try {
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: e164Phone,
        forceResendingToken: forceResendingToken,
        timeout: const Duration(seconds: 120),
        verificationCompleted: (credential) {
          _autoCredential = credential;
          if (!completer.isCompleted) {
            completer.complete(
              PhoneChallenge(
                verificationId: credential.verificationId ?? '',
                e164Phone: e164Phone,
                maskedPhone: PhoneMask.mask(e164Phone),
                resendToken: forceResendingToken,
                resendAttempt: resendAttempt,
                autoVerified: true,
              ),
            );
          }
        },
        verificationFailed: (error) {
          if (!completer.isCompleted) {
            completer.completeError(AuthErrorMapper.map(error));
          }
        },
        codeSent: (verificationId, resendToken) {
          _sendCount += 1;
          if (!completer.isCompleted) {
            completer.complete(
              PhoneChallenge(
                verificationId: verificationId,
                e164Phone: e164Phone,
                maskedPhone: PhoneMask.mask(e164Phone),
                resendToken: resendToken,
                resendAttempt: resendAttempt,
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (_) {
          // Do not treat auto-retrieval timeout as "SMS sent".
        },
      );
      return await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw const AuthException(
            AuthMessages.smsFailed,
            kind: AuthErrorKind.smsFailed,
          );
        },
      );
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  @override
  Future<AuthSession> completeAutoVerification() async {
    final credential = _autoCredential;
    _autoCredential = null;
    if (credential == null) {
      throw const AuthException(
        AuthMessages.smsFailed,
        kind: AuthErrorKind.smsFailed,
      );
    }
    try {
      final result = await _firebaseAuth.signInWithCredential(credential);
      return _sessionFrom(result);
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  @override
  Future<AuthSession> verifyCode({
    required PhoneChallenge challenge,
    required String smsCode,
  }) async {
    final error = OtpValidator.validate(smsCode);
    if (error != null) {
      throw AuthException(error, kind: AuthErrorKind.invalidOtp);
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: challenge.verificationId,
        smsCode: OtpValidator.digitsOnly(smsCode),
      );
      final result = await _firebaseAuth.signInWithCredential(credential);
      return _sessionFrom(result);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  @override
  Future<AuthSession> linkCode({
    required PhoneChallenge challenge,
    required String smsCode,
  }) async {
    final current = _firebaseAuth.currentUser;
    if (current == null) {
      throw const AuthException(
        AuthMessages.unknown,
        kind: AuthErrorKind.unknown,
      );
    }
    final error = OtpValidator.validate(smsCode);
    if (error != null) {
      throw AuthException(error, kind: AuthErrorKind.invalidOtp);
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: challenge.verificationId,
        smsCode: OtpValidator.digitsOnly(smsCode),
      );
      final result = await current.linkWithCredential(credential);
      return _sessionFrom(result);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  @override
  void resetSendCount() {
    _sendCount = 0;
  }

  AuthSession _sessionFrom(UserCredential result) {
    final user = result.user;
    if (user == null) {
      throw const AuthException(
        AuthMessages.smsFailed,
        kind: AuthErrorKind.smsFailed,
      );
    }
    return AuthSession(
      uid: user.uid,
      provider: AuthProviderId.phone,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      phoneNumber: user.phoneNumber,
      persistEmail: false,
      persistDisplayName: false,
      isNewUser: result.additionalUserInfo?.isNewUser ?? false,
    );
  }
}

typedef FirebasePhoneAuthService = PhoneAuthService;
