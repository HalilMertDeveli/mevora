import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';

class AccountDeletionService {
  AccountDeletionService({
    required AppConfig config,
    required this.googleAuthService,
    this.onAccountDeleted,
    FirebaseFunctions? functions,
    FirebaseAuth? firebaseAuth,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: config.functionsRegion),
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final GoogleAuthService googleAuthService;

  /// Runs once the account is known to be deleted on the server, before the
  /// local sign-out: the place to drop what this device still holds for the
  /// account.
  final Future<void> Function(String uid)? onAccountDeleted;
  final FirebaseFunctions _functions;
  final FirebaseAuth _firebaseAuth;

  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthException(
        AuthMessages.unknown,
        kind: AuthErrorKind.unknown,
      );
    }
    try {
      final callable = _functions.httpsCallable('deleteUserAccount');
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{},
      );
      final payload = response.data;

      final ok = payload['ok'] == true;
      final deleted = payload['deleted'] == true;
      if (!ok || !deleted) {
        throw AuthException(
          kDebugMode
              ? 'Delete account failed: $payload'
              : AuthMessages.unknown,
          kind: AuthErrorKind.unknown,
          code: payload['code'].toString(),
        );
      }

      // Only sign out locally once server deletion is confirmed.
      await closeDeletedSession(user.uid);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated' ||
          error.code == 'failed-precondition') {
        throw const AuthException(
          AuthMessages.oauth,
          kind: AuthErrorKind.oauth,
        );
      }
      throw AuthErrorMapper.map(error);
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  /// Ends this device's session for [uid], an account the server no longer
  /// has: drops what the device still holds for it, then signs out.
  ///
  /// Called once the server confirmed the deletion, and for a restored
  /// session whose account turns out to be gone. The clean-up before the
  /// sign-out is best-effort and can never skip it: a device must not stay
  /// signed in to an account that no longer exists.
  Future<void> closeDeletedSession(String uid) async {
    try {
      await onAccountDeleted?.call(uid);
    } on Object {
      // Local cleanup is best-effort; the account is already gone.
    }
    try {
      await googleAuthService.signOut();
    } on Object {
      // Google session cleanup is best-effort.
    }
    // Another account may have signed in meanwhile; leave it alone.
    if (_firebaseAuth.currentUser?.uid == uid) {
      await _firebaseAuth.signOut();
    }
  }
}
