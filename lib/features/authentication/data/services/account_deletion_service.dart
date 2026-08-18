import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';

class AccountDeletionService {
  AccountDeletionService({
    required AppConfig config,
    required this.googleAuthService,
    FirebaseFunctions? functions,
    FirebaseAuth? firebaseAuth,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: config.functionsRegion),
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final GoogleAuthService googleAuthService;
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
      await callable.call<Map<String, dynamic>>(<String, dynamic>{});
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
    } finally {
      try {
        await googleAuthService.signOut();
        await _firebaseAuth.signOut();
      } on Object {
        // Local session cleanup is best-effort after server deletion.
      }
    }
  }
}
