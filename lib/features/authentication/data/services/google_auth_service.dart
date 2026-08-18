import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';

class GoogleAuthService {
  GoogleAuthService({
    required this.serverClientId,
    GoogleSignIn? googleSignIn,
    FirebaseAuth? firebaseAuth,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final String serverClientId;
  final GoogleSignIn _googleSignIn;
  final FirebaseAuth _firebaseAuth;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await _googleSignIn.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    _initialized = true;
  }

  Future<AuthSession> signIn() async {
    try {
      await _ensureInitialized();
      final account = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          AuthMessages.oauth,
          kind: AuthErrorKind.oauth,
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _firebaseAuth.signInWithCredential(credential);
      return _sessionFrom(result, account);
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException(
          AuthMessages.cancelled,
          kind: AuthErrorKind.cancelled,
          isCancelled: true,
        );
      }
      throw AuthErrorMapper.map(error);
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  Future<AuthSession> link() async {
    final current = _firebaseAuth.currentUser;
    if (current == null) {
      throw const AuthException(
        AuthMessages.unknown,
        kind: AuthErrorKind.unknown,
      );
    }
    try {
      await _ensureInitialized();
      final account = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          AuthMessages.oauth,
          kind: AuthErrorKind.oauth,
        );
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await current.linkWithCredential(credential);
      return _sessionFrom(result, account);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await _googleSignIn.signOut();
    } on Object {
      // Google session cleanup is best-effort.
    }
  }

  AuthSession _sessionFrom(
    UserCredential result,
    GoogleSignInAccount account,
  ) {
    final user = result.user;
    if (user == null) {
      throw const AuthException(
        AuthMessages.oauth,
        kind: AuthErrorKind.oauth,
      );
    }
    return AuthSession(
      uid: user.uid,
      provider: AuthProviderId.google,
      email: account.email,
      displayName: account.displayName ?? user.displayName,
      photoUrl: account.photoUrl ?? user.photoURL,
      persistDisplayName: true,
      persistEmail: true,
      isNewUser: result.additionalUserInfo?.isNewUser ?? false,
    );
  }
}
