import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/features/authentication/data/models/user_document.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';

abstract class UserRemoteDataSource {
  Stream<UserDocument?> watchUser(String uid);

  Future<AuthUser> upsertFromSession(AuthSession session);

  Future<AuthUser> fetchUser(String uid);

  Future<AuthUser?> findUser(String uid);
}

/// Account reads/writes for `users/{uid}`. Dating fields are written to
/// `profiles/{uid}` in the same batch so AuthUser still hydrates.
class FirebaseUserDataSource implements UserRemoteDataSource {
  FirebaseUserDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static final Map<String, Future<AuthUser>> _upsertInFlight =
      <String, Future<AuthUser>>{};

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestorePaths.users);

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection(FirestorePaths.profiles);

  @override
  Stream<UserDocument?> watchUser(String uid) {
    return watchAccountAndProfile(
      uid: uid,
      account: _users
          .doc(uid)
          .snapshots()
          .where(
            (snap) => !isCachedRestriction(
              snap.exists ? snap.data() : null,
              fromCache: snap.metadata.isFromCache,
            ),
          )
          .map((snap) => snap.exists ? (snap.data() ?? const {}) : null),
      profile: _profiles
          .doc(uid)
          .snapshots()
          .map((snap) => snap.data() ?? const <String, dynamic>{}),
    );
  }

  /// True for a locally cached account snapshot that says the account is
  /// restricted (banned, deleted, disabled or suspended).
  ///
  /// Such a snapshot is held back until the server's copy arrives. Firestore
  /// emits the cached document first, so a member whose ban was just lifted
  /// used to sign in, see the stale "banned" copy and be signed straight back
  /// out as banned (found in runtime QA). Waiting costs nothing for a real
  /// restriction: the server copy says the same thing a moment later, and a
  /// banned account cannot refresh its session anyway.
  @visibleForTesting
  static bool isCachedRestriction(
    Map<String, dynamic>? account, {
    required bool fromCache,
  }) {
    if (!fromCache || account == null) {
      return false;
    }
    final status = AccountStatusX.fromFirestore(
      account['accountStatus'],
      legacyIsBanned: account['isBanned'] as bool?,
      legacyIsActive: account['isActive'] as bool?,
      legacyIsSuspended: account['isSuspended'] as bool?,
      suspendedUntil: null,
    );
    return status != AccountStatus.active;
  }

  /// Combines the private account and the public profile into one live
  /// [UserDocument].
  ///
  /// Both documents are watched. The profile used to be read once per
  /// account change, so anything that changes only there — photos being
  /// approved after upload, a new main photo, a renamed profile — never
  /// reached the signed-in user until something else touched the account
  /// (the avatar kept showing initials over approved photos).
  ///
  /// A missing account emits null at once (the profile is still pending).
  /// Otherwise nothing is emitted until both have been seen, and a change
  /// that leaves the derived user identical is not re-emitted, so the many
  /// profile writes during onboarding do not re-announce the same user.
  @visibleForTesting
  static Stream<UserDocument?> watchAccountAndProfile({
    required String uid,
    required Stream<Map<String, dynamic>?> account,
    required Stream<Map<String, dynamic>> profile,
  }) {
    return Stream<UserDocument?>.multi((controller) {
      Map<String, dynamic>? accountData;
      Map<String, dynamic>? profileData;
      var accountSeen = false;
      var lastWasNull = false;
      AuthUser? lastUser;

      void emit() {
        if (!accountSeen) {
          return;
        }
        final currentAccount = accountData;
        if (currentAccount == null) {
          if (!lastWasNull) {
            lastWasNull = true;
            lastUser = null;
            controller.add(null);
          }
          return;
        }
        final currentProfile = profileData;
        if (currentProfile == null) {
          return;
        }
        final doc = UserDocument.fromAccountAndProfile(
          uid: uid,
          account: currentAccount,
          profile: currentProfile,
        );
        final user = doc.toEntity();
        if (!lastWasNull && user == lastUser) {
          return;
        }
        lastWasNull = false;
        lastUser = user;
        controller.add(doc);
      }

      final accountSub = account.listen((data) {
        accountData = data;
        accountSeen = true;
        emit();
      }, onError: controller.addError);
      final profileSub = profile.listen((data) {
        profileData = data;
        emit();
      }, onError: controller.addError);
      controller.onCancel = () async {
        await accountSub.cancel();
        await profileSub.cancel();
      };
    });
  }

  @override
  Future<AuthUser> fetchUser(String uid) async {
    final user = await findUser(uid);
    if (user == null) {
      throw const AuthException(
        AuthMessages.unknown,
        kind: AuthErrorKind.unknown,
      );
    }
    ensureSignInAllowed(user);
    return user;
  }

  /// A suspended member signs in into the restricted state (the router
  /// holds them on the restricted screen, from which they can appeal).
  /// Banned, deleted and disabled accounts are refused.
  @visibleForTesting
  static void ensureSignInAllowed(AuthUser user) {
    if (!user.isSuspended && (user.isBanned || !user.isActive)) {
      throw const AuthException(
        AuthMessages.banned,
        kind: AuthErrorKind.banned,
      );
    }
  }

  @override
  Future<AuthUser?> findUser(String uid) async {
    final accountSnap = await _users.doc(uid).get();
    if (!accountSnap.exists) {
      return null;
    }
    final profileSnap = await _profiles.doc(uid).get();
    return UserDocument.fromAccountAndProfile(
      uid: uid,
      account: accountSnap.data() ?? const {},
      profile: profileSnap.data() ?? const {},
    ).toEntity();
  }

  @override
  Future<AuthUser> upsertFromSession(AuthSession session) {
    final uid = session.uid;
    // Coalesce concurrent upserts for the same uid (e.g. sign-in + auth snapshot).
    return _upsertInFlight[uid] ??= _runUpsert(
      session,
    ); // ignore: unawaited_futures
  }

  Future<AuthUser> _runUpsert(AuthSession session) async {
    final uid = session.uid;
    try {
      return await _upsertFromSessionLocked(session);
    } finally {
      _upsertInFlight.remove(uid); // ignore: unawaited_futures
    }
  }

  Future<AuthUser> _upsertFromSessionLocked(AuthSession session) async {
    final uid = session.uid;
    final accountRef = _users.doc(uid);
    final profileRef = _profiles.doc(uid);
    final prefsRef = _firestore
        .collection(FirestorePaths.userPreferences)
        .doc(uid);
    final settingsRef = _firestore
        .collection(FirestorePaths.userSettings)
        .doc(uid);
    final privacyRef = _firestore
        .collection(FirestorePaths.userPrivacy)
        .doc(uid);
    // lastActiveAt must be FieldValue.serverTimestamp() — rules reject
    // arbitrary client dates so users cannot stay in the discovery pool.
    final now = FieldValue.serverTimestamp();

    // Avoid runTransaction: Flutter's MethodChannel completer double-fires on
    // cancel/abort (Bad state: Future already completed). Read then WriteBatch.
    final accountSnap = await accountRef.get();
    final profileSnap = await profileRef.get();

    if (accountSnap.exists) {
      final existing = accountSnap.data() ?? const <String, dynamic>{};
      if (_isBanned(existing)) {
        throw const AuthException(
          AuthMessages.banned,
          kind: AuthErrorKind.banned,
        );
      }

      final batch = _firestore.batch();
      batch.update(accountRef, _accountUpdates(session, existing, now));

      if (!profileSnap.exists) {
        batch.set(profileRef, _newProfileStub(session, now));
      } else if (session.persistDisplayName &&
          _isPresent(session.displayName)) {
        final profile = profileSnap.data() ?? const <String, dynamic>{};
        if (!_isPresent(profile['displayName'])) {
          batch.update(profileRef, {
            'displayName': session.displayName,
            'updatedAt': now,
          });
        }
      }
      await batch.commit();
    } else {
      final batch = _firestore.batch();
      batch.set(accountRef, _newAccount(session, now));
      batch.set(profileRef, _newProfileStub(session, now));
      batch.set(prefsRef, _defaultPreferences(now));
      batch.set(settingsRef, _defaultSettings(now));
      batch.set(privacyRef, _defaultPrivacy(now));
      await batch.commit();
    }

    return fetchUser(uid);
  }

  static bool _isBanned(Map<String, dynamic> existing) {
    return existing['accountStatus'] == AccountStatus.banned.firestoreValue ||
        existing['isBanned'] == true;
  }

  Map<String, dynamic> _newAccount(AuthSession session, FieldValue now) {
    final provider = session.provider;
    return {
      'uid': session.uid,
      'id': session.uid,
      'displayName': session.persistDisplayName ? session.displayName : null,
      'email': session.email,
      'phoneNumber': session.phoneNumber,
      'photoUrl': session.photoUrl,
      'phoneVerified': false,
      'authProviders': {
        'email': provider == AuthProviderId.email,
        'google': provider == AuthProviderId.google,
        'apple': provider == AuthProviderId.apple,
        'spotify': provider == AuthProviderId.spotify,
        'phone': provider == AuthProviderId.phone,
      },
      'createdAt': now,
      'updatedAt': now,
      'lastLoginAt': now,
      'lastActiveAt': now,
      'profileCompleted': false,
      'onboardingCompleted': false,
      'isActive': true,
      'isBanned': false,
      'isVerified': false,
      'accountStatus': AccountStatus.active.firestoreValue,
    };
  }

  Map<String, dynamic> _accountUpdates(
    AuthSession session,
    Map<String, dynamic> existing,
    FieldValue now,
  ) {
    final updates = <String, dynamic>{
      'lastLoginAt': now,
      'lastActiveAt': now,
      'updatedAt': now,
      'uid': session.uid,
      'id': session.uid,
      'isActive': true,
    };
    final provider = session.provider;
    if (provider != null) {
      updates['authProviders.${provider.name}'] = true;
    }
    if (session.persistEmail && _isPresent(session.email)) {
      updates['email'] = session.email;
    } else if (!_isPresent(existing['email']) && _isPresent(session.email)) {
      updates['email'] = session.email;
    }
    if (session.persistDisplayName &&
        _isPresent(session.displayName) &&
        !_isPresent(existing['displayName'])) {
      updates['displayName'] = session.displayName;
    }
    if (_isPresent(session.photoUrl) && !_isPresent(existing['photoUrl'])) {
      updates['photoUrl'] = session.photoUrl;
    }
    if (_isPresent(session.phoneNumber)) {
      updates['phoneNumber'] = session.phoneNumber;
    }
    return updates;
  }

  Map<String, dynamic> _newProfileStub(AuthSession session, FieldValue now) {
    return {
      'uid': session.uid,
      'displayName': session.displayName,
      'photos': const <Map<String, dynamic>>[],
      'interests': const <String>[],
      'languages': const <String>[],
      'profileCompleted': false,
      'onboardingCompleted': false,
      'isDiscoverable': false,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  Map<String, dynamic> _defaultPreferences(FieldValue now) {
    return {
      'preferredGender': null,
      'minAge': 18,
      'maxAge': 99,
      'maxDistance': 50,
      'relationshipGoals': const <String>[],
      'interests': const <String>[],
      'showMe': null,
      'discoveryEnabled': true,
      'updatedAt': now,
    };
  }

  Map<String, dynamic> _defaultSettings(FieldValue now) {
    return {
      'language': 'en',
      'theme': 'system',
      'notificationsEnabled': true,
      'messageNotifications': true,
      'matchNotifications': true,
      'callNotifications': true,
      'locationEnabled': false,
      'locationOnboardingCompleted': false,
      'showOnlineStatus': true,
      'updatedAt': now,
    };
  }

  Map<String, dynamic> _defaultPrivacy(FieldValue now) {
    return {
      'showOnlineStatus': true,
      'showLastSeen': true,
      'showTypingStatus': true,
      'showDistance': true,
      'showAge': true,
      'showActivity': true,
      'allowNotifications': true,
      'allowCalls': true,
      'allowMessages': true,
      'updatedAt': now,
    };
  }

  static bool _isPresent(Object? value) {
    return value is String && value.trim().isNotEmpty;
  }
}

/// Existing name used by auth composition. Delegates to the account datasource.
class FirestoreUserRemoteDataSource extends FirebaseUserDataSource {
  FirestoreUserRemoteDataSource({super.firestore});
}
