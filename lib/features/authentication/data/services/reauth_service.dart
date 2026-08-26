import 'package:mevora/features/authentication/data/services/email_auth_service.dart';
import 'package:mevora/features/authentication/data/services/google_auth_service.dart';

/// Reauthentication for sensitive actions (change password, delete account).
abstract class ReauthPort {
  Future<void> reauthenticateWithPassword(String password);

  Future<void> reauthenticateWithGoogle();
}

class ReauthService implements ReauthPort {
  ReauthService({
    required GoogleAuthService googleAuthService,
    EmailAuthService? emailAuthService,
  }) : _googleAuthService = googleAuthService,
       _emailAuthService = emailAuthService ?? EmailAuthService();

  final GoogleAuthService _googleAuthService;
  final EmailAuthService _emailAuthService;

  @override
  Future<void> reauthenticateWithPassword(String password) {
    return _emailAuthService.reauthenticateWithPassword(password);
  }

  @override
  Future<void> reauthenticateWithGoogle() {
    return _googleAuthService.reauthenticate();
  }
}
