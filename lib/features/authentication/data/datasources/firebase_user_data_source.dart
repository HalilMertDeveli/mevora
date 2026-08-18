import 'package:cloud_firestore/cloud_firestore.dart';
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

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestorePaths.users);

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection(FirestorePaths.profiles);

  @override
  Stream<UserDocument?> watchUser(String uid) {
    return _users.doc(uid).snapshots().asyncMap((snap) async {
      if (!snap.exists) {
        return null;
      }
      final profile = await _profiles.doc(uid).get();
      return UserDocument.fromAccountAndProfile(
        uid: uid,
        account: snap.data() ?? const {},
        profile: profile.data() ?? const {},
      );
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
    if (user.isBanned || !user.isActive) {
      throw const AuthException(
        AuthMessages.banned,
        kind: AuthErrorKind.banned,
      );
    }
    return user;
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
  Future<AuthUser> upsertFromSession(AuthSession session) async {
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
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(accountRef);
      if (!snap.exists) {
        transaction.set(accountRef, _newAccount(session, now));
        transaction.set(profileRef, _newProfileStub(session, now));
        transaction.set(prefsRef, _defaultPreferences(now));
        transaction.set(settingsRef, _defaultSettings(now));
        transaction.set(privacyRef, _defaultPrivacy(now));
        return;
      }

      final existing = snap.data() ?? const <String, dynamic>{};
      final banned =
          existing['accountStatus'] == AccountStatus.banned.firestoreValue ||
          existing['isBanned'] == true;
      if (banned) {
        throw const AuthException(
          AuthMessages.banned,
          kind: AuthErrorKind.banned,
        );
      }

      transaction.update(accountRef, _accountUpdates(session, existing, now));

      final profileSnap = await transaction.get(profileRef);
      if (!profileSnap.exists) {
        transaction.set(profileRef, _newProfileStub(session, now));
      } else if (session.persistDisplayName && _isPresent(session.displayName)) {
        transaction.update(profileRef, {
          'displayName': session.displayName,
          'updatedAt': now,
        });
      }
    });

    return fetchUser(uid);
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
    if (session.persistDisplayName && _isPresent(session.displayName)) {
      updates['displayName'] = session.displayName;
    }
    if (_isPresent(session.photoUrl)) {
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
      'showDistance': true,
      'showAge': true,
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
