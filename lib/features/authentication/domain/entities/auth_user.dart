import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    this.email,
    this.displayName,
    this.phoneNumber,
    this.photoUrl,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.authProviders = const AuthProviders(),
    this.createdAt,
    this.lastLoginAt,
    this.lastActiveAt,
    this.profileCompleted = false,
    this.onboardingCompleted = false,
    this.isActive = true,
    this.isBanned = false,
    this.isVerified = false,
  });

  final String id;
  final String? email;
  final String? displayName;
  final String? phoneNumber;
  final String? photoUrl;
  final bool emailVerified;

  /// Set only from trusted backend sync of Firebase Auth. Never true from the client.
  final bool phoneVerified;
  final AuthProviders authProviders;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final DateTime? lastActiveAt;
  final bool profileCompleted;
  final bool onboardingCompleted;
  final bool isActive;
  final bool isBanned;
  final bool isVerified;

  bool get isProfileComplete => profileCompleted || onboardingCompleted;

  bool get shouldOnboard => isActive && !isBanned && !isProfileComplete;

  bool get canEnterDiscovery => isActive && !isBanned && isProfileComplete;

  AuthUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? phoneNumber,
    String? photoUrl,
    bool? emailVerified,
    bool? phoneVerified,
    AuthProviders? authProviders,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    DateTime? lastActiveAt,
    bool? profileCompleted,
    bool? onboardingCompleted,
    bool? isActive,
    bool? isBanned,
    bool? isVerified,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      authProviders: authProviders ?? this.authProviders,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      isActive: isActive ?? this.isActive,
      isBanned: isBanned ?? this.isBanned,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AuthUser &&
        other.id == id &&
        other.email == email &&
        other.displayName == displayName &&
        other.phoneNumber == phoneNumber &&
        other.photoUrl == photoUrl &&
        other.emailVerified == emailVerified &&
        other.phoneVerified == phoneVerified &&
        other.authProviders == authProviders &&
        other.createdAt == createdAt &&
        other.lastLoginAt == lastLoginAt &&
        other.lastActiveAt == lastActiveAt &&
        other.profileCompleted == profileCompleted &&
        other.onboardingCompleted == onboardingCompleted &&
        other.isActive == isActive &&
        other.isBanned == isBanned &&
        other.isVerified == isVerified;
  }

  @override
  int get hashCode => Object.hash(
    id,
    email,
    displayName,
    phoneNumber,
    photoUrl,
    emailVerified,
    phoneVerified,
    authProviders,
    createdAt,
    lastLoginAt,
    lastActiveAt,
    profileCompleted,
    onboardingCompleted,
    isActive,
    isBanned,
    isVerified,
  );
}
