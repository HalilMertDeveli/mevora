import 'dart:async';

import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/utils/phone_mask.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_snapshot.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/repositories/auth_repository.dart';
import 'package:mevora/features/authentication/domain/repositories/user_document_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.user,
    this.sendResult,
    this.verifyResult,
    this.sendDelay = Duration.zero,
  });

  AuthUser? user;
  Result<PhoneChallenge>? sendResult;
  Result<AuthUser>? verifyResult;
  Duration sendDelay;
  String? lastSmsCode;
  String? lastE164Phone;
  final _controller = StreamController<AuthUser?>.broadcast();
  String? lastResetEmail;
  String? lastEmail;
  bool passwordSubmitted = false;
  int signInCalls = 0;
  int registerCalls = 0;
  bool googleCalled = false;
  bool appleCalled = false;
  bool spotifyCalled = false;
  bool signedOut = false;
  AuthProviderId? lastLinkedProvider;
  Failure? nextFailure;
  Duration googleDelay = Duration.zero;
  AuthUser? googleUser;

  void emit(AuthUser? value) {
    user = value;
    _controller.add(value);
  }

  AuthSnapshot _snapshotFor(AuthUser? value) {
    if (value == null) {
      return const AuthSignedOut();
    }
    return AuthProfileReady(value);
  }

  @override
  Stream<AuthUser?> watchAuthState() async* {
    yield user;
    yield* _controller.stream;
  }

  @override
  Stream<AuthSnapshot> watchAuth() async* {
    yield _snapshotFor(user);
    yield* _controller.stream.map(_snapshotFor);
  }

  @override
  Future<Result<AuthUser>> registerWithEmail({
    required String email,
    required String password,
  }) {
    lastEmail = email.trim();
    passwordSubmitted = password.isNotEmpty;
    registerCalls += 1;
    return _complete(
      AuthUser(
        id: 'user-1',
        email: email.trim(),
        authProviders: const AuthProviders(email: true),
      ),
    );
  }

  @override
  Future<Result<AuthUser>> signInWithEmail({
    required String email,
    required String password,
  }) {
    lastEmail = email.trim();
    passwordSubmitted = password.isNotEmpty;
    signInCalls += 1;
    return _complete(
      AuthUser(
        id: 'user-1',
        email: email.trim(),
        authProviders: const AuthProviders(email: true),
      ),
    );
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    lastResetEmail = email;
    if (nextFailure != null) {
      return Err(nextFailure!);
    }
    return const Success(null);
  }

  @override
  Future<Result<AuthUser>> signInWithGoogle() async {
    googleCalled = true;
    if (googleDelay > Duration.zero) {
      await Future<void>.delayed(googleDelay);
    }
    return _complete(
      googleUser ??
          const AuthUser(
            id: 'google-1',
            email: 'ada@mevora.app',
            authProviders: AuthProviders(google: true),
          ),
    );
  }

  @override
  Future<Result<AuthUser>> signInWithApple() {
    appleCalled = true;
    return _complete(const AuthUser(id: 'apple-1', email: 'ada@mevora.app'));
  }

  @override
  Future<Result<AuthUser>> signInWithSpotify() {
    spotifyCalled = true;
    return _complete(
      const AuthUser(
        id: 'spotify-1',
        displayName: 'Spotify User',
        onboardingCompleted: true,
        profileCompleted: true,
      ),
    );
  }

  @override
  Future<Result<PhoneChallenge>> sendPhoneVerificationCode(
    String e164Phone,
  ) async {
    lastE164Phone = e164Phone;
    if (sendDelay > Duration.zero) {
      await Future<void>.delayed(sendDelay);
    }
    if (sendResult != null) {
      return sendResult!;
    }
    return Success(
      PhoneChallenge(
        verificationId: 'vid',
        e164Phone: e164Phone,
        maskedPhone: PhoneMask.mask(e164Phone),
      ),
    );
  }

  @override
  Future<Result<PhoneChallenge>> resendPhoneVerificationCode(
    PhoneChallenge challenge,
  ) async {
    if (sendResult != null) {
      return sendResult!;
    }
    if (nextFailure != null) {
      return Err(nextFailure!);
    }
    return Success(
      PhoneChallenge(
        verificationId: 'vid-resend-${challenge.resendAttempt + 1}',
        e164Phone: challenge.e164Phone,
        maskedPhone: challenge.maskedPhone,
        resendToken: challenge.resendToken ?? 1,
        resendAttempt: challenge.resendAttempt + 1,
      ),
    );
  }

  @override
  Future<Result<AuthUser>> completePhoneAutoVerification() {
    if (verifyResult != null) {
      return Future.value(verifyResult);
    }
    return _complete(
      AuthUser(
        id: 'phone-auto-1',
        phoneNumber: user?.phoneNumber,
        onboardingCompleted: true,
        profileCompleted: true,
        authProviders: const AuthProviders(phone: true),
      ),
    );
  }

  @override
  Future<Result<AuthUser>> verifyPhoneCode({
    required PhoneChallenge challenge,
    required String smsCode,
  }) {
    lastSmsCode = smsCode;
    if (verifyResult != null) {
      return Future.value(verifyResult);
    }
    if (nextFailure != null) {
      return Future.value(Err(nextFailure!));
    }
    if (smsCode != '123456') {
      return Future.value(
        const Err(
          AuthFailure(
            AuthMessages.invalidOtp,
            kind: AuthErrorKind.invalidOtp,
          ),
        ),
      );
    }
    return _complete(
      AuthUser(
        id: 'phone-1',
        phoneNumber: challenge.e164Phone,
        onboardingCompleted: true,
        profileCompleted: true,
        authProviders: const AuthProviders(phone: true),
      ),
    );
  }

  @override
  Future<Result<AuthUser>> linkProvider(AuthProviderId provider) {
    lastLinkedProvider = provider;
    final current = user;
    if (current == null) {
      return _unsupported();
    }
    return _complete(
      current.copyWith(authProviders: current.authProviders.withProvider(provider)),
    );
  }

  @override
  Future<Result<AuthUser>> linkEmail({
    required String email,
    required String password,
  }) {
    lastEmail = email.trim();
    passwordSubmitted = password.isNotEmpty;
    lastLinkedProvider = AuthProviderId.email;
    final current = user;
    if (current == null) {
      return _unsupported();
    }
    return _complete(
      current.copyWith(
        email: email.trim(),
        authProviders: current.authProviders.withProvider(AuthProviderId.email),
      ),
    );
  }

  @override
  Future<Result<PhoneChallenge>> sendPhoneLinkCode(String e164Phone) {
    return _unsupported();
  }

  @override
  Future<Result<AuthUser>> verifyPhoneLinkCode({
    required PhoneChallenge challenge,
    required String smsCode,
  }) {
    return _unsupported();
  }

  @override
  Future<void> restorePendingOAuth() async {}

  @override
  Future<Result<void>> signOut() async {
    if (nextFailure != null) {
      return Err(nextFailure!);
    }
    emit(null);
    signedOut = true;
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteAccount() async {
    return signOut();
  }

  Future<Result<AuthUser>> _complete(AuthUser next) async {
    if (nextFailure != null) {
      return Err(nextFailure!);
    }
    emit(next);
    return Success(next);
  }

  Future<Result<T>> _unsupported<T>() async {
    return const Err(
      AuthFailure(
        'This sign-in method is not part of Phase 3.',
        kind: AuthErrorKind.notConfigured,
      ),
    );
  }

  void dispose() {
    unawaited(_controller.close());
  }
}

class FakeUserDocumentRepository implements UserDocumentRepository {
  FakeUserDocumentRepository({this.complete = false});

  bool complete;
  AuthUser? ensured;

  @override
  Future<void> ensureUserDocument(AuthUser user) async {
    ensured = user;
  }

  @override
  Future<bool> isProfileComplete(String userId) async => complete;
}
