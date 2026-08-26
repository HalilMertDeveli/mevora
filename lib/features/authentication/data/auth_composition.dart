import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/cache/firestore_session_cache.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/data/datasources/user_remote_datasource.dart';
import 'package:mevora/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:mevora/features/authentication/data/repositories/user_document_repository_impl.dart';
import 'package:mevora/features/authentication/data/services/account_deletion_service.dart';
import 'package:mevora/features/authentication/data/services/apple_auth_service.dart';
import 'package:mevora/features/authentication/data/services/auth_analytics.dart';
import 'package:mevora/features/authentication/data/services/email_auth_service.dart';
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';
import 'package:mevora/features/authentication/data/services/phone_auth_service.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';

AuthController createAuthController({
  required AppConfig config,
  required AppLogger logger,
  AuthAnalytics? analytics,
  SpotifyAuthService? spotifyAuthService,
}) {
  final userRemote = FirestoreUserRemoteDataSource();
  final google = GoogleAuthService(serverClientId: config.googleWebClientId);
  final authAnalytics = analytics ?? FirebaseAuthAnalytics();
  final messaging = FirebaseMessagingDataSource();
  final sessionCache = FirestoreSessionCache(logger: logger);
  return AuthController(
    authRepository: AuthRepositoryImpl(
      emailAuthService: EmailAuthService(),
      googleAuthService: google,
      appleAuthService: AppleAuthService(config: config),
      spotifyAuthService: spotifyAuthService ?? SpotifyAuthService(config: config),
      phoneAuthService: PhoneAuthService(),
      userRemoteDataSource: userRemote,
      accountSync: FirebaseFunctionsCallable(region: config.functionsRegion),
      accountDeletionService: AccountDeletionService(
        config: config,
        googleAuthService: google,
      ),
      firebaseAuth: FirebaseAuth.instance,
      onBeforeSignOut: (uid) async {
        final token = (await messaging.getToken()).valueOrNull;
        if (token == null) {
          return;
        }
        try {
          await messaging.unregisterDevice(uid: uid, token: token);
        } on Object {
          // Device token cleanup is best-effort.
        }
      },
      onAfterSignOut: sessionCache.clearSensitiveCache,
    ),
    userDocumentRepository: UserDocumentRepositoryImpl(userRemote),
    logger: logger,
    analytics: authAnalytics,
  );
}
