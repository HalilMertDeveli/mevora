import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_snapshot.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/entities/restored_session_check.dart';

/// Authentication port. Presentation never talks to FirebaseAuth.
abstract class AuthRepository {
  Stream<AuthUser?> watchAuthState();

  Stream<AuthSnapshot> watchAuth();

  /// Asks Firebase Auth whether the account behind the restored session
  /// [uid] still exists, and closes the session on this device when it can
  /// never recover.
  ///
  /// A session restored from the device outlives the account: the cached ID
  /// token keeps passing the security rules for up to an hour after the
  /// account was deleted. Call this before writing account documents for a
  /// session nobody just signed in to. Never throws.
  Future<RestoredSessionCheck> verifyRestoredSession(String uid);

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

  Future<Result<AuthUser>> linkEmail({
    required String email,
    required String password,
  });

  Future<Result<PhoneChallenge>> sendPhoneLinkCode(String e164Phone);

  Future<Result<AuthUser>> verifyPhoneLinkCode({
    required PhoneChallenge challenge,
    required String smsCode,
  });

  Future<Result<void>> signOut();

  Future<Result<void>> deleteAccount();

  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

}
