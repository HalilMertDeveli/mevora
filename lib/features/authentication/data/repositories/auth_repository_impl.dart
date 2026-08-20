import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/utils/otp_validator.dart';
import 'package:mevora/features/authentication/data/datasources/user_remote_datasource.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/data/services/account_deletion_service.dart';
import 'package:mevora/features/authentication/data/services/apple_auth_service.dart';
import 'package:mevora/features/authentication/data/services/email_auth_service.dart';
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';
import 'package:mevora/features/authentication/data/services/phone_auth_service.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:mevora/features/authentication/domain/entities/auth_snapshot.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required EmailAuthService emailAuthService,
    required GoogleAuthService googleAuthService,
    required AppleAuthService appleAuthService,
    required SpotifyAuthService spotifyAuthService,
    required PhoneAuthService phoneAuthService,
    required UserRemoteDataSource userRemoteDataSource,
    required AccountDeletionService accountDeletionService,
    FirebaseAuth? firebaseAuth,
    BackendCallable? accountSync,
    Future<void> Function(String uid)? onBeforeSignOut,
    Future<void> Function()? onAfterSignOut,
  }) : _emailAuthService = emailAuthService,
       _googleAuthService = googleAuthService,
       _appleAuthService = appleAuthService,
       _spotifyAuthService = spotifyAuthService,
       _phoneAuthService = phoneAuthService,
       _userRemoteDataSource = userRemoteDataSource,
       _accountDeletionService = accountDeletionService,
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _accountSync = accountSync,
       _onBeforeSignOut = onBeforeSignOut,
       _onAfterSignOut = onAfterSignOut;

  final EmailAuthService _emailAuthService;
  final GoogleAuthService _googleAuthService;
  final AppleAuthService _appleAuthService;
  final SpotifyAuthService _spotifyAuthService;
  final PhoneAuthService _phoneAuthService;
  final UserRemoteDataSource _userRemoteDataSource;
  final AccountDeletionService _accountDeletionService;
  final FirebaseAuth _firebaseAuth;
  final BackendCallable? _accountSync;
  final Future<void> Function(String uid)? _onBeforeSignOut;
  final Future<void> Function()? _onAfterSignOut;

  @override
  Stream<AuthUser?> watchAuthState() {
    return watchAuth().map((snapshot) {
      return switch (snapshot) {
        AuthProfileReady(:final user) => user,
        AuthSignedOut() || AuthProfilePending() => null,
      };
    });
  }

  @override
  Stream<AuthSnapshot> watchAuth() {
    // switchMap: cancel the previous users/{uid} listener when auth changes.
    // asyncExpand would concatenate and never process sign-out while watchUser
    // is still open, then permission-denied crashes after logout.
    return Stream<AuthSnapshot>.multi((listener) {
      StreamSubscription<User?>? authSub;
      StreamSubscription<AuthSnapshot>? innerSub;

      Future<void> listenInner(Stream<AuthSnapshot> stream) async {
        await innerSub?.cancel();
        innerSub = stream.listen(
          listener.add,
          onError: (Object error, StackTrace stackTrace) {
            if (_isAuthSessionGone(error)) {
              listener.add(const AuthSignedOut());
              return;
            }
            listener.addError(error, stackTrace);
          },
        );
      }

      authSub = _firebaseAuth.authStateChanges().listen(
        (firebaseUser) {
          if (firebaseUser == null) {
            unawaited(
              listenInner(
                Stream<AuthSnapshot>.value(const AuthSignedOut()),
              ),
            );
            return;
          }
          unawaited(
            listenInner(
              _userRemoteDataSource.watchUser(firebaseUser.uid).map((doc) {
                if (doc == null) {
                  return AuthProfilePending(firebaseUser.uid);
                }
                return AuthProfileReady(
                  doc.toEntity().copyWith(
                    emailVerified: firebaseUser.emailVerified,
                  ),
                );
              }),
            ),
          );
        },
        onError: listener.addError,
      );

      listener.onCancel = () async {
        await innerSub?.cancel();
        await authSub?.cancel();
      };
    });
  }

  @override
  Future<Result<AuthUser>> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _run(() async {
      final session = await _emailAuthService.register(
        email: email,
        password: password,
      );
      return _userRemoteDataSource.upsertFromSession(session);
    });
  }

  @override
  Future<Result<AuthUser>> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _run(() async {
      final session = await _emailAuthService.signIn(
        email: email,
        password: password,
      );
      return _userRemoteDataSource.upsertFromSession(session);
    });
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) {
    return _run(() => _emailAuthService.sendPasswordResetEmail(email));
  }

  @override
  Future<Result<AuthUser>> signInWithGoogle() {
    return _run(() async {
      final session = await _googleAuthService.signIn();
      return _userRemoteDataSource.upsertFromSession(session);
    });
  }

  @override
  Future<Result<AuthUser>> signInWithApple() {
    return _run(() async {
      final session = await _appleAuthService.signIn();
      return _userRemoteDataSource.upsertFromSession(session);
    });
  }

  @override
  Future<Result<AuthUser>> signInWithSpotify() {
    return _run(() async {
      final session = await _spotifyAuthService.signIn(
        linkToCurrentUser: false,
      );
      return _userRemoteDataSource.upsertFromSession(session);
    });
  }

  @override
  Future<Result<PhoneChallenge>> sendPhoneVerificationCode(String e164Phone) {
    return _run(() => _phoneAuthService.sendCode(e164Phone));
  }

  @override
  Future<Result<PhoneChallenge>> resendPhoneVerificationCode(
    PhoneChallenge challenge,
  ) {
    if (challenge.resendAttempt >= OtpValidator.maxResendAttempts) {
      return Future.value(
        Err(FailureMapper.from(AuthErrorMapper.fromCode('too-many-requests'))),
      );
    }
    return _run(
      () => _phoneAuthService.sendCode(
        challenge.e164Phone,
        forceResendingToken: challenge.resendToken,
        resendAttempt: challenge.resendAttempt + 1,
      ),
    );
  }

  @override
  Future<Result<AuthUser>> completePhoneAutoVerification() {
    return _run(() async {
      final session = await _phoneAuthService.completeAutoVerification();
      return _persistPhoneSession(session);
    });
  }

  @override
  Future<Result<AuthUser>> verifyPhoneCode({
    required PhoneChallenge challenge,
    required String smsCode,
  }) {
    return _run(() async {
      final session = await _phoneAuthService.verifyCode(
        challenge: challenge,
        smsCode: smsCode,
      );
      return _persistPhoneSession(session);
    });
  }

  @override
  Future<Result<AuthUser>> linkProvider(AuthProviderId provider) {
    return _run(() async {
      final session = switch (provider) {
        AuthProviderId.google => await _googleAuthService.link(),
        AuthProviderId.apple => await _appleAuthService.link(),
        AuthProviderId.spotify => await _spotifyAuthService.signIn(
          linkToCurrentUser: true,
        ),
        AuthProviderId.phone => throw AuthErrorMapper.fromCode('invalid-phone'),
        AuthProviderId.email => throw AuthErrorMapper.fromCode('not-configured'),
      };
      return _userRemoteDataSource.upsertFromSession(session);
    });
  }

  @override
  Future<Result<AuthUser>> linkEmail({
    required String email,
    required String password,
  }) {
    return _run(() async {
      final session = await _emailAuthService.link(
        email: email,
        password: password,
      );
      return _userRemoteDataSource.upsertFromSession(session);
    });
  }

  @override
  Future<Result<PhoneChallenge>> sendPhoneLinkCode(String e164Phone) {
    return sendPhoneVerificationCode(e164Phone);
  }

  @override
  Future<Result<AuthUser>> verifyPhoneLinkCode({
    required PhoneChallenge challenge,
    required String smsCode,
  }) {
    return _run(() async {
      final session = await _phoneAuthService.linkCode(
        challenge: challenge,
        smsCode: smsCode,
      );
      return _persistPhoneSession(session);
    });
  }

  @override
  Future<Result<void>> signOut() {
    return _run(() async {
      final uid = _firebaseAuth.currentUser?.uid;
      if (uid != null) {
        try {
          await _onBeforeSignOut?.call(uid);
        } on Object {
          // FCM unregister is best-effort and must not block session close.
        }
      }
      try {
        await _googleAuthService.signOut();
      } on Object {
        // Google session cleanup is best-effort.
      }
      try {
        if (_firebaseAuth.currentUser != null) {
          await _firebaseAuth.signOut();
        }
      } on Object {
        if (_firebaseAuth.currentUser != null) {
          rethrow;
        }
      }
      try {
        _phoneAuthService.resetSendCount();
      } on Object {
        // Local OTP counters are best-effort.
      }
      try {
        await _onAfterSignOut?.call();
      } on Object {
        // Firestore cache wipe is best-effort.
      }
    });
  }

  @override
  Future<Result<void>> deleteAccount() {
    return _run(_accountDeletionService.deleteAccount);
  }

  @override
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _run(
      () => _emailAuthService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
  }

  @override
  Future<void> restorePendingOAuth() {
    return _spotifyAuthService.handleInitialUri();
  }

  Future<AuthUser> _persistPhoneSession(AuthSession session) async {
    await _userRemoteDataSource.upsertFromSession(session);
    final sync = _accountSync;
    if (sync != null) {
      try {
        await sync.invoke('syncAuthAccount');
      } catch (_) {
        // Client never sets phoneVerified. Auth remains the source of truth.
      }
    }
    return _userRemoteDataSource.fetchUser(session.uid);
  }

  Future<Result<T>> _run<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  static bool _isAuthSessionGone(Object error) {
    final message = error.toString();
    return message.contains('permission-denied') ||
        message.contains('PERMISSION_DENIED') ||
        message.contains('unauthenticated');
  }
}
