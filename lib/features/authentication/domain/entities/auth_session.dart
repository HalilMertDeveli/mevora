import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';

/// Identity payload returned by an authentication service after OAuth/phone.
class AuthSession {
  const AuthSession({
    required this.uid,
    required this.provider,
    this.email,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
    this.isNewUser = false,
    this.persistDisplayName = false,
    this.persistEmail = false,
  });

  final String uid;
  final AuthProviderId? provider;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final bool isNewUser;

  /// Apple only provides the full name on the first authorization.
  final bool persistDisplayName;
  final bool persistEmail;
}
