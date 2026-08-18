import 'dart:async';

import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/utils/phone_mask.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
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
  final _controller = StreamController<AuthUser?>.broadcast();
  String? lastResetEmail;
  bool googleCalled = false;
  bool appleCalled = false;
  bool spotifyCalled = false;
  bool signedOut = false;
  AuthProviderId? lastLinkedProvider;
  Failure? nextFailure;

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
    return _complete(AuthUser(id: 'user-1', email: email.trim()));
  }

  @override
  Future<Result<AuthUser>> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _complete(AuthUser(id: 'user-1', email: email.trim()));
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
  Future<Result<AuthUser>> signInWithGoogle() {
    googleCalled = true;
    return _complete(const AuthUser(id: 'google-1', email: 'ada@mevora.app'));
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
  ) {
    if (sendResult != null) {
      return Future.value(sendResult);
    }
    return _unsupported();
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
      ),
    );
  }

  @override
  Future<Result<AuthUser>> completePhoneAutoVerification() {
    return _unsupported();
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
