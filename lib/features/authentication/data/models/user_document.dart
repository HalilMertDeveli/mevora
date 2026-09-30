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
      legacyIsSuspended: account['isSuspended'] as bool?,
      suspendedUntil: firestoreDate(account['suspendedUntil']),
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

  /// The member's own portrait: the approved photo marked as main, else the
  /// first approved photo by the order they arranged, else the first in the
  /// stored list. Array position alone is not the member's order.
  static String? _firstApprovedPhoto(Object? photos) {
    if (photos is! List || photos.isEmpty) {
      return null;
    }
    final approved = <({String url, bool primary, int order, int index})>[];
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (photo is Map) {
        final status = photo['moderationStatus'];
        final url = photo['downloadUrl'] ?? photo['thumbUrl'];
        if (url is String &&
            url.isNotEmpty &&
            (status == null || status == 'approved')) {
          final order = photo['order'];
          approved.add((
            url: url,
            primary: photo['isPrimary'] == true,
            order: order is num ? order.toInt() : i,
            index: i,
          ));
        }
      } else if (photo is String && photo.isNotEmpty) {
        approved.add((url: photo, primary: false, order: i, index: i));
      }
    }
    if (approved.isEmpty) {
      return null;
    }
    approved.sort((a, b) {
      if (a.primary != b.primary) {
        return a.primary ? -1 : 1;
      }
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.index.compareTo(b.index);
    });
    return approved.first.url;
  }
}
