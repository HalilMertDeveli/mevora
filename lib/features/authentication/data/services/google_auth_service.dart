import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
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

  // #region agent log
  void _logDebug(
    String message, {
    String hypothesisId = 'GAUTH',
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    try {
      final entry = <String, Object?>{
        'sessionId': '80971b',
        'runId': 'google-signin',
        'hypothesisId': hypothesisId,
        'location': 'google_auth_service.dart',
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      // Visible in `flutter run` output from physical devices.
      // ignore: avoid_print
      print('[GAUTH_DEBUG] ${jsonEncode(entry)}');
    } on Object {
      // Ignore logging errors.
    }
  }
  // #endregion

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    // #region agent log
    _logDebug(
      'google_initialize_start',
      data: <String, Object?>{
        'serverClientIdEmpty': serverClientId.isEmpty,
      },
    );
    // #endregion
    await _googleSignIn.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    _initialized = true;
    // #region agent log
    _logDebug('google_initialize_ok');
    // #endregion
  }

  Future<AuthSession> signIn() async {
    try {
      await _ensureInitialized();
      // #region agent log
      _logDebug('google_authenticate_start');
      // #endregion
      final account = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      // #region agent log
      _logDebug(
        'google_authenticate_ok',
        data: <String, Object?>{
          'email': account.email,
          'hasDisplayName': (account.displayName ?? '').isNotEmpty,
          'hasPhotoUrl': (account.photoUrl ?? '').isNotEmpty,
        },
      );
      // #endregion
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        // #region agent log
        _logDebug('google_missing_id_token', hypothesisId: 'GAUTH_TOKEN');
        // #endregion
        throw const AuthException(
          AuthMessages.oauth,
          kind: AuthErrorKind.oauth,
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      // #region agent log
      _logDebug('firebase_signin_with_google_credential_start');
      // #endregion
      final result = await _firebaseAuth.signInWithCredential(credential);
      // #region agent log
      _logDebug(
        'firebase_signin_with_google_credential_ok',
        data: <String, Object?>{
          'hasUser': result.user != null,
          'isNewUser': result.additionalUserInfo?.isNewUser,
        },
      );
      // #endregion
      return _sessionFrom(result, account);
    } on AuthException {
      // #region agent log
      _logDebug('google_auth_exception_passthrough', hypothesisId: 'GAUTH_AUTH');
      // #endregion
      rethrow;
    } on GoogleSignInException catch (error) {
      // CredMan often reports misconfigured package/SHA as "canceled".
      assert(() {
        // ignore: avoid_print
        print(
          'GoogleSignInException code=${error.code} '
          'description=${error.description} details=${error.details}',
        );
        return true;
      }());
      if (error.code == GoogleSignInExceptionCode.canceled) {
        // #region agent log
        _logDebug(
          'google_signin_exception_canceled',
          hypothesisId: 'GAUTH_CANCEL',
          data: <String, Object?>{
            'description': error.description,
            'details': error.details?.toString(),
          },
        );
        // #endregion
        throw const AuthException(
          AuthMessages.cancelled,
          kind: AuthErrorKind.cancelled,
          isCancelled: true,
        );
      }
      // #region agent log
      _logDebug(
        'google_signin_exception_other',
        hypothesisId: 'GAUTH_EXCEPTION',
        data: <String, Object?>{
          'code': error.code.name,
          'description': error.description,
          'details': error.details?.toString(),
        },
      );
      // #endregion
      throw AuthErrorMapper.map(error);
    } on Object catch (error) {
      // #region agent log
      _logDebug(
        'google_signin_unknown_error',
        hypothesisId: 'GAUTH_UNKNOWN',
        data: <String, Object?>{'error': error.toString()},
      );
      // #endregion
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

  /// Reauthenticates the current Firebase user with Google (delete account, etc.).
  Future<void> reauthenticate() async {
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
      await current.reauthenticateWithCredential(credential);
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
    // Prefill identity hints for onboarding only — never auto-complete dating
    // profile fields (photos, interests, etc.).
    final isNewUser = result.additionalUserInfo?.isNewUser ?? false;
    return AuthSession(
      uid: user.uid,
      provider: AuthProviderId.google,
      email: account.email,
      displayName: account.displayName ?? user.displayName,
      photoUrl: account.photoUrl ?? user.photoURL,
      persistDisplayName: isNewUser,
      persistEmail: true,
      isNewUser: isNewUser,
    );
  }
}
