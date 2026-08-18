import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';

class AuthProviders {
  const AuthProviders({
    this.email = false,
    this.google = false,
    this.apple = false,
    this.spotify = false,
    this.phone = false,
  });

  final bool email;
  final bool google;
  final bool apple;
  final bool spotify;
  final bool phone;

  bool get hasAny => email || google || apple || spotify || phone;

  AuthProviders copyWith({
    bool? email,
    bool? google,
    bool? apple,
    bool? spotify,
    bool? phone,
  }) {
    return AuthProviders(
      email: email ?? this.email,
      google: google ?? this.google,
      apple: apple ?? this.apple,
      spotify: spotify ?? this.spotify,
      phone: phone ?? this.phone,
    );
  }

  AuthProviders withProvider(AuthProviderId provider) {
    return switch (provider) {
      AuthProviderId.email => copyWith(email: true),
      AuthProviderId.google => copyWith(google: true),
      AuthProviderId.apple => copyWith(apple: true),
      AuthProviderId.spotify => copyWith(spotify: true),
      AuthProviderId.phone => copyWith(phone: true),
    };
  }

  bool isLinked(AuthProviderId provider) {
    return switch (provider) {
      AuthProviderId.email => email,
      AuthProviderId.google => google,
      AuthProviderId.apple => apple,
      AuthProviderId.spotify => spotify,
      AuthProviderId.phone => phone,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AuthProviders &&
        other.email == email &&
        other.google == google &&
        other.apple == apple &&
        other.spotify == spotify &&
        other.phone == phone;
  }

  @override
  int get hashCode => Object.hash(email, google, apple, spotify, phone);
}
