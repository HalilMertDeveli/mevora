import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';

/// Account document at `users/{uid}`. Dating fields live on `profiles/{uid}`.
class UserDocument {
  const UserDocument({
    required this.id,
    this.displayName,
    this.email,
    this.phoneNumber,
    this.phoneVerified = false,
    this.photoUrl,
    this.authProviders = const AuthProviders(),
    this.createdAt,
    this.lastLoginAt,
    this.lastActiveAt,
    this.updatedAt,
    this.profileCompleted = false,
    this.onboardingCompleted = false,
    this.accountStatus = AccountStatus.active,
    this.isVerified = false,
  });

  final String id;
  final String? displayName;
  final String? email;
  final String? phoneNumber;
  final bool phoneVerified;
  final String? photoUrl;
  final AuthProviders authProviders;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final DateTime? lastActiveAt;
  final DateTime? updatedAt;
  final bool profileCompleted;
  final bool onboardingCompleted;
  final AccountStatus accountStatus;
  final bool isVerified;

  bool get isBanned => accountStatus.isBanned;

  bool get isActive => accountStatus.isActive;

  bool get isProfileComplete => profileCompleted || onboardingCompleted;

  factory UserDocument.fromMap(String id, Map<String, dynamic> data) {
    return UserDocument.fromAccountAndProfile(
      uid: id,
      account: data,
      profile: const {},
    );
  }

  factory UserDocument.fromAccountAndProfile({
    required String uid,
    required Map<String, dynamic> account,
    required Map<String, dynamic> profile,
  }) {
    final providers = account['authProviders'];
    final status = AccountStatusX.fromFirestore(
      account['accountStatus'],
      legacyIsBanned: account['isBanned'] as bool?,
      legacyIsActive: account['isActive'] as bool?,
    );
    return UserDocument(
      id: uid,
      email: account['email'] as String?,
      phoneNumber: account['phoneNumber'] as String?,
      phoneVerified: firestoreFlag(account['phoneVerified']),
      authProviders: AuthProviders(
        google: firestoreFlag(providers is Map ? providers['google'] : null),
        apple: firestoreFlag(providers is Map ? providers['apple'] : null),
        spotify: firestoreFlag(providers is Map ? providers['spotify'] : null),
        phone: firestoreFlag(providers is Map ? providers['phone'] : null),
        email: firestoreFlag(providers is Map ? providers['email'] : null),
      ),
      createdAt: firestoreDate(account['createdAt']),
      lastLoginAt: firestoreDate(account['lastLoginAt']),
      lastActiveAt: firestoreDate(account['lastActiveAt']),
      updatedAt: firestoreDate(account['updatedAt']),
      accountStatus: status,
      isVerified: firestoreFlag(account['isVerified']),
      displayName:
          (profile['displayName'] as String?) ??
          (account['displayName'] as String?),
      photoUrl:
          _firstApprovedPhoto(profile['photos']) ??
          (profile['photoUrl'] as String?) ??
          (account['photoUrl'] as String?),
      profileCompleted:
          firestoreFlag(profile['profileCompleted']) ||
          firestoreFlag(account['profileCompleted']),
      onboardingCompleted:
          firestoreFlag(profile['onboardingCompleted']) ||
          firestoreFlag(account['onboardingCompleted']),
    );
  }

  factory UserDocument.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    return UserDocument.fromMap(snap.id, snap.data() ?? const {});
  }

  AuthUser toEntity() {
    return AuthUser(
      id: id,
      displayName: displayName,
      email: email,
      phoneNumber: phoneNumber,
      photoUrl: photoUrl,
      emailVerified: false,
      phoneVerified: phoneVerified,
      authProviders: authProviders,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      lastActiveAt: lastActiveAt,
      profileCompleted: profileCompleted,
      onboardingCompleted: onboardingCompleted,
      isActive: isActive,
      isBanned: isBanned,
      isVerified: isVerified,
    );
  }

  static String? _firstApprovedPhoto(Object? photos) {
    if (photos is! List || photos.isEmpty) {
      return null;
    }
    for (final photo in photos) {
      if (photo is Map) {
        final status = photo['moderationStatus'];
        final url = photo['downloadUrl'] ?? photo['thumbUrl'];
        if (url is String &&
            url.isNotEmpty &&
            (status == null || status == 'approved')) {
          return url;
        }
      } else if (photo is String && photo.isNotEmpty) {
        return photo;
      }
    }
    return null;
  }
}
