import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/repositories/auth_repository.dart';

class RegisterWithEmail {
  const RegisterWithEmail(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call({
    required String email,
    required String password,
  }) {
    return _repository.registerWithEmail(email: email, password: password);
  }
}

class SignInWithEmail {
  const SignInWithEmail(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call({
    required String email,
    required String password,
  }) {
    return _repository.signInWithEmail(email: email, password: password);
  }
}

class SendPasswordResetEmail {
  const SendPasswordResetEmail(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call(String email) {
    return _repository.sendPasswordResetEmail(email);
  }
}

class SignInWithGoogle {
  const SignInWithGoogle(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call() => _repository.signInWithGoogle();
}

class SignInWithApple {
  const SignInWithApple(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call() => _repository.signInWithApple();
}

class SignInWithSpotify {
  const SignInWithSpotify(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call() => _repository.signInWithSpotify();
}

class SendPhoneVerificationCode {
  const SendPhoneVerificationCode(this._repository);

  final AuthRepository _repository;

  Future<Result<PhoneChallenge>> call(String e164Phone) {
    return _repository.sendPhoneVerificationCode(e164Phone);
  }
}

class VerifyPhoneCode {
  const VerifyPhoneCode(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call({
    required PhoneChallenge challenge,
    required String smsCode,
  }) {
    return _repository.verifyPhoneCode(
      challenge: challenge,
      smsCode: smsCode,
    );
  }
}

class ResendPhoneVerificationCode {
  const ResendPhoneVerificationCode(this._repository);

  final AuthRepository _repository;

  Future<Result<PhoneChallenge>> call(PhoneChallenge challenge) {
    return _repository.resendPhoneVerificationCode(challenge);
  }
}

class SignOut {
  const SignOut(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call() => _repository.signOut();
}

class DeleteAccount {
  const DeleteAccount(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call() => _repository.deleteAccount();
}

class LinkAuthProvider {
  const LinkAuthProvider(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call(AuthProviderId provider) {
    return _repository.linkProvider(provider);
  }
}
