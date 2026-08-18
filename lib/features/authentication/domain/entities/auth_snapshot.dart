import 'package:mevora/features/authentication/domain/entities/auth_user.dart';

sealed class AuthSnapshot {
  const AuthSnapshot();
}

final class AuthSignedOut extends AuthSnapshot {
  const AuthSignedOut();
}

/// Firebase session exists but the Firestore user document is not ready yet.
final class AuthProfilePending extends AuthSnapshot {
  const AuthProfilePending(this.uid);

  final String uid;
}

final class AuthProfileReady extends AuthSnapshot {
  const AuthProfileReady(this.user);

  final AuthUser user;

  AuthUser get next => user;
}
