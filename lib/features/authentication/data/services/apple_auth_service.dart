import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/data/pkce.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' hide generateNonce;

class AppleAuthService {
  AppleAuthService({FirebaseAuth? firebaseAuth, this.config})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  final AppConfig? config;

  Future<AuthSession> signIn() => _authenticate(link: false);

  Future<AuthSession> link() => _authenticate(link: true);

  Future<AuthSession> _authenticate({required bool link}) async {
    if (!_isApplePlatform) {
      throw const AuthException(
        AppStrings.appleSignInUnavailable,
        kind: AuthErrorKind.notConfigured,
      );
    }
    try {
      final rawNonce = generateNonce();
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256ofString(rawNonce),
      );
      final identityToken = apple.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw const AuthException(
          AppStrings.authAppleFailed,
          kind: AuthErrorKind.oauth,
        );
      }

      final oauth = OAuthProvider('apple.com').credential(
        idToken: identityToken,
        rawNonce: rawNonce,
      );
      final UserCredential result;
      if (link) {
        final current = _firebaseAuth.currentUser;
        if (current == null) {
          throw const AuthException(
            AuthMessages.unknown,
            kind: AuthErrorKind.unknown,
          );
        }
        result = await current.linkWithCredential(oauth);
      } else {
        result = await _firebaseAuth.signInWithCredential(oauth);
      }
      return _sessionFrom(result, apple);
    } on AuthException {
      rethrow;
    } on SignInWithAppleNotSupportedException catch (error) {
      throw AuthException(
        AppStrings.appleSignInUnavailable,
        kind: AuthErrorKind.notConfigured,
        cause: error,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
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
    AuthorizationCredentialAppleID apple,
  ) {
    final user = result.user;
    if (user == null) {
      throw const AuthException(
        AppStrings.authAppleFailed,
        kind: AuthErrorKind.oauth,
      );
    }

    final given = apple.givenName?.trim() ?? '';
    final family = apple.familyName?.trim() ?? '';
    final composed = '$given $family'.trim();
    final displayName = composed.isEmpty ? null : composed;

    return AuthSession(
      uid: user.uid,
      provider: AuthProviderId.apple,
      email: apple.email ?? user.email,
      displayName: displayName ?? user.displayName,
      photoUrl: user.photoURL,
      persistDisplayName: displayName != null,
      persistEmail: apple.email != null && apple.email!.isNotEmpty,
      isNewUser: result.additionalUserInfo?.isNewUser ?? false,
    );
  }

  bool get _isApplePlatform {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}
