import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_snapshot.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';

/// Authentication port. Presentation never talks to FirebaseAuth.
abstract class AuthRepository {
  Stream<AuthUser?> watchAuthState();

  Stream<AuthSnapshot> watchAuth();

  Future<Result<AuthUser>> registerWithEmail({
    required String email,
    required String password,
  });

  Future<Result<AuthUser>> signInWithEmail({
    required String email,
    required String password,
  });

  Future<Result<void>> sendPasswordResetEmail(String email);

  Future<Result<AuthUser>> signInWithGoogle();

  Future<Result<AuthUser>> signInWithApple();

  Future<Result<AuthUser>> signInWithSpotify();

  Future<Result<PhoneChallenge>> sendPhoneVerificationCode(String e164Phone);

  Future<Result<PhoneChallenge>> resendPhoneVerificationCode(
    PhoneChallenge challenge,
  );

  Future<Result<AuthUser>> verifyPhoneCode({
    required PhoneChallenge challenge,
    required String smsCode,
  });

  Future<Result<AuthUser>> completePhoneAutoVerification();

  Future<Result<AuthUser>> linkProvider(AuthProviderId provider);

  Future<Result<PhoneChallenge>> sendPhoneLinkCode(String e164Phone);

  Future<Result<AuthUser>> verifyPhoneLinkCode({
    required PhoneChallenge challenge,
    required String smsCode,
  });

  Future<Result<void>> signOut();

  Future<Result<void>> deleteAccount();

  /// Completes an in-flight OAuth callback after process resume (Spotify).
  Future<void> restorePendingOAuth();
}
