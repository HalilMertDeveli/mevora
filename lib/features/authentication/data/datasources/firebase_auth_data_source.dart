import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';

/// Low-level Firebase Auth phone operations. Widgets and domain never call
/// `FirebaseAuth.instance`. Implemented by [PhoneAuthService].
abstract class FirebaseAuthDataSource {
  Future<PhoneChallenge> sendCode(
    String e164Phone, {
    int? forceResendingToken,
    int resendAttempt,
  });

  Future<AuthSession> verifyCode({
    required PhoneChallenge challenge,
    required String smsCode,
  });

  Future<AuthSession> linkCode({
    required PhoneChallenge challenge,
    required String smsCode,
  });

  Future<AuthSession> completeAutoVerification();

  void resetSendCount();
}
