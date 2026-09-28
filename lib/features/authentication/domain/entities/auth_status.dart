import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';

/// Global authentication states. Routing must key off this, not widget locals.
sealed class AuthStatus {
  const AuthStatus();

  static const AuthInitializing unknown = AuthInitializing();
  static const Unauthenticated unauthenticated = Unauthenticated();
  static const Authenticating authenticating = Authenticating();
  static const NeedsOnboarding needsOnboarding = NeedsOnboarding();
  static const AuthenticationError error = AuthenticationError('');
  static const Authenticated authenticated = Authenticated(
    AuthUser(
      id: 'complete',
      profileCompleted: true,
      onboardingCompleted: true,
    ),
  );
}

final class AuthInitializing extends AuthStatus {
  const AuthInitializing();
}

final class Unauthenticated extends AuthStatus {
  const Unauthenticated();
}

final class Authenticating extends AuthStatus {
  const Authenticating({this.provider});

  final String? provider;
}

final class Authenticated extends AuthStatus {
  const Authenticated(this.user);

  final AuthUser user;
}

final class NeedsOnboarding extends AuthStatus {
  const NeedsOnboarding([this.user]);

  final AuthUser? user;
}

final class AuthenticationError extends AuthStatus {
  const AuthenticationError(this.message);

  final String message;
}

final class PhoneCodeSent extends AuthStatus {
  const PhoneCodeSent(this.challenge);

  final PhoneChallenge challenge;
}

final class PhoneVerificationRequired extends AuthStatus {
  const PhoneVerificationRequired(this.challenge);

  final PhoneChallenge challenge;
}
