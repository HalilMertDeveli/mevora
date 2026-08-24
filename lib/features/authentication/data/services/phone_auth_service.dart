import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
  Completer<PhoneChallenge>? _inFlightSend;

  void _log(String stage, [String? detail]) {
    // Never log phone numbers, OTP codes, or secrets.
    final suffix = detail == null || detail.isEmpty ? '' : ' $detail';
    // ignore: avoid_print
    print('[PHONE_AUTH] $stage$suffix');
  }

  @override
  Future<PhoneChallenge> sendCode(
    String e164Phone, {
    int? forceResendingToken,
    int resendAttempt = 0,
  }) async {
    _log('START', 'resendAttempt=$resendAttempt hasResendToken=${forceResendingToken != null}');
    if (!PhoneMask.isValidE164(e164Phone)) {
      _log('PHONE_NORMALIZED', 'invalid');
      throw const AuthException(
        AuthMessages.invalidPhone,
        kind: AuthErrorKind.invalidPhone,
        code: 'invalid-phone-number',
      );
    }
    _log('PHONE_NORMALIZED', 'ok length=${e164Phone.length} country=${e164Phone.length >= 3 ? e164Phone.substring(0, 3) : "?"}');
    if (_sendCount >= OtpValidator.maxResendAttempts + 1) {
      _log('VERIFICATION_FAILED', 'code=too-many-requests local-limit');
      throw const AuthException(
        AuthMessages.tooManyAttempts,
        kind: AuthErrorKind.tooManyAttempts,
        code: 'too-many-requests',
      );
    }
    final existing = _inFlightSend;
    if (existing != null && !existing.isCompleted) {
      _log('VERIFICATION_FAILED', 'code=sms-in-flight');
      throw const AuthException(
        AuthMessages.smsInFlight,
        kind: AuthErrorKind.smsFailed,
        code: 'sms-in-flight',
      );
    }

    final completer = Completer<PhoneChallenge>();
    _inFlightSend = completer;

    try {
      _log('VERIFY_STARTED');
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: e164Phone,
        forceResendingToken: forceResendingToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) {
          _autoCredential = credential;
          _log(
            'VERIFICATION_COMPLETED',
            'hasVerificationId=${credential.verificationId != null && credential.verificationId!.isNotEmpty}',
          );
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
          _log(
            'VERIFICATION_FAILED',
            'code=${error.code} message=${error.message}',
          );
          if (kDebugMode) {
            _log('VERIFICATION_FAILED', 'plugin=${error.plugin} details=${error.toString()}');
          }
          if (!completer.isCompleted) {
            completer.completeError(AuthErrorMapper.map(error));
          }
        },
        codeSent: (verificationId, resendToken) {
          _sendCount += 1;
          final emptyId = verificationId.trim().isEmpty;
          _log(
            'CODE_SENT',
            'verificationIdEmpty=$emptyId hasResendToken=${resendToken != null} sendCount=$_sendCount',
          );
          if (emptyId) {
            if (!completer.isCompleted) {
              completer.completeError(
                const AuthException(
                  AuthMessages.smsFailed,
                  kind: AuthErrorKind.smsFailed,
                  code: 'missing-verification-id',
                ),
              );
            }
            return;
          }
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
        codeAutoRetrievalTimeout: (verificationId) {
          // If codeSent already completed the future, this is a no-op.
          // If verification never reached codeSent (stuck reCAPTCHA / Integrity),
          // fail instead of hanging until the outer timeout.
          if (!completer.isCompleted && verificationId.isNotEmpty) {
            _sendCount += 1;
            _log('CODE_SENT', 'via=autoRetrievalTimeout verificationIdEmpty=false');
            completer.complete(
              PhoneChallenge(
                verificationId: verificationId,
                e164Phone: e164Phone,
                maskedPhone: PhoneMask.mask(e164Phone),
                resendToken: forceResendingToken,
                resendAttempt: resendAttempt,
              ),
            );
          } else if (!completer.isCompleted) {
            _log('VERIFICATION_FAILED', 'code=auto-retrieval-timeout emptyId');
            completer.completeError(
              const AuthException(
                AuthMessages.smsFailed,
                kind: AuthErrorKind.smsFailed,
                code: 'auto-retrieval-timeout',
              ),
            );
          }
        },
      );
      return await completer.future.timeout(
        const Duration(seconds: 75),
        onTimeout: () {
          _log('VERIFICATION_FAILED', 'code=client-timeout');
          throw const AuthException(
            AuthMessages.smsFailed,
            kind: AuthErrorKind.smsFailed,
            code: 'client-timeout',
          );
        },
      );
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      _log('VERIFICATION_FAILED', 'code=mapper error=$error');
      throw AuthErrorMapper.map(error);
    } finally {
      if (identical(_inFlightSend, completer)) {
        _inFlightSend = null;
      }
    }
  }

  @override
  Future<AuthSession> completeAutoVerification() async {
    final credential = _autoCredential;
    _autoCredential = null;
    if (credential == null) {
      _log('CREDENTIAL_CREATED', 'auto=false missing');
      throw const AuthException(
        AuthMessages.smsFailed,
        kind: AuthErrorKind.smsFailed,
        code: 'missing-auto-credential',
      );
    }
    _log('CREDENTIAL_CREATED', 'auto=true');
    try {
      _log('SIGN_IN_STARTED', 'mode=auto');
      final result = await _firebaseAuth.signInWithCredential(credential);
      return _sessionFrom(result);
    } on Object catch (error) {
      _log('VERIFICATION_FAILED', 'code=sign-in-auto error=$error');
      throw AuthErrorMapper.map(error);
    }
  }

  @override
  Future<AuthSession> verifyCode({
    required PhoneChallenge challenge,
    required String smsCode,
  }) async {
    _log(
      'OTP_SUBMITTED',
      'verificationIdEmpty=${challenge.verificationId.isEmpty} codeLength=${OtpValidator.digitsOnly(smsCode).length}',
    );
    final error = OtpValidator.validate(smsCode);
    if (error != null) {
      throw AuthException(error, kind: AuthErrorKind.invalidOtp, code: 'invalid-otp-format');
    }
    if (challenge.verificationId.trim().isEmpty) {
      _log('CREDENTIAL_CREATED', 'failed missing-verification-id');
      throw const AuthException(
        AuthMessages.sessionExpired,
        kind: AuthErrorKind.sessionExpired,
        code: 'missing-verification-id',
      );
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: challenge.verificationId,
        smsCode: OtpValidator.digitsOnly(smsCode),
      );
      _log('CREDENTIAL_CREATED', 'manual=true');
      _log('SIGN_IN_STARTED', 'mode=manual');
      final result = await _firebaseAuth.signInWithCredential(credential);
      return _sessionFrom(result);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      _log('VERIFICATION_FAILED', 'code=sign-in-manual error=$error');
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
        code: 'no-current-user',
      );
    }
    final error = OtpValidator.validate(smsCode);
    if (error != null) {
      throw AuthException(error, kind: AuthErrorKind.invalidOtp, code: 'invalid-otp-format');
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: challenge.verificationId,
        smsCode: OtpValidator.digitsOnly(smsCode),
      );
      _log('CREDENTIAL_CREATED', 'link=true');
      _log('SIGN_IN_STARTED', 'mode=link');
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
      _log('SIGN_IN_SUCCESS', 'uid=null');
      throw const AuthException(
        AuthMessages.smsFailed,
        kind: AuthErrorKind.smsFailed,
        code: 'null-user',
      );
    }
    _log('SIGN_IN_SUCCESS');
    _log('FIREBASE_UID_RECEIVED', 'isNewUser=${result.additionalUserInfo?.isNewUser == true}');
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
