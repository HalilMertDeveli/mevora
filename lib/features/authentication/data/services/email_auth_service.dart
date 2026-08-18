import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';

class EmailAuthService {
  EmailAuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  Future<AuthSession> register({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _sendVerificationBestEffort(result.user);
      return _sessionFrom(result);
    } on FirebaseAuthException catch (error) {
      throw AuthErrorMapper.fromCode(error.code, cause: error);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _sessionFrom(result);
    } on FirebaseAuthException catch (error) {
      throw AuthErrorMapper.fromCode(error.code, cause: error);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      if (_isUnknownAccount(error.code)) {
        return;
      }
      throw AuthErrorMapper.fromCode(error.code, cause: error);
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  Future<AuthSession> link({
    required String email,
    required String password,
  }) async {
    final current = _firebaseAuth.currentUser;
    if (current == null) {
      throw AuthErrorMapper.fromCode('unknown');
    }
    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      final result = await current.linkWithCredential(credential);
      await _sendVerificationBestEffort(result.user);
      return _sessionFrom(result);
    } on FirebaseAuthException catch (error) {
      throw AuthErrorMapper.fromCode(error.code, cause: error);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  Future<void> _sendVerificationBestEffort(User? user) async {
    if (user == null || user.emailVerified) {
      return;
    }
    try {
      await user.sendEmailVerification();
    } on Object {
      // Registration / linking still succeeds; verification is not a gate.
    }
  }

  static bool _isUnknownAccount(String code) {
    final normalized = code.toLowerCase().replaceAll('_', '-');
    return normalized == 'user-not-found';
  }

  AuthSession _sessionFrom(UserCredential result) {
    final user = result.user;
    if (user == null) {
      throw const AuthException(
        'We could not complete that request. Please try again.',
        kind: AuthErrorKind.unknown,
      );
    }
    return AuthSession(
      uid: user.uid,
      provider: AuthProviderId.email,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      persistEmail: user.email != null,
      isNewUser: result.additionalUserInfo?.isNewUser ?? false,
    );
  }
}
