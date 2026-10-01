import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/paging/page.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/validators/person_name_validator.dart';

class FirebaseProfileDataSource {
  FirebaseProfileDataSource({
    FirebaseFirestore? firestore,
    BackendCallable? backend,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _backend = backend;

  final FirebaseFirestore _firestore;
  final BackendCallable? _backend;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection(FirestorePaths.profiles);

  CollectionReference<Map<String, dynamic>> get _accounts =>
      _firestore.collection(FirestorePaths.users);

  CollectionReference<Map<String, dynamic>> get _preferences =>
      _firestore.collection(FirestorePaths.userPreferences);

  Future<UserProfile?> fetch(String uid) async {
    final snap = await _profiles.doc(uid).get();
    if (!snap.exists) {
      return null;
    }
    return _profileFrom(snap.id, snap.data() ?? const {});
  }

  Stream<UserProfile?> watch(String uid) {
    return _profiles.doc(uid).snapshots().map((snap) {
      if (!snap.exists) {
        return null;
      }
      return _profileFrom(snap.id, snap.data() ?? const {});
    });
  }

  Future<void> save(UserProfile profile) {
    return _profiles.doc(profile.uid).set(publicProfileMap(profile), SetOptions(merge: true));
  }

  /// The owner's private surname. It lives on `users/{uid}`, which only its
  /// owner can read; `profiles/{uid}` is readable by every member and never
  /// carries it.
  Future<String?> fetchLastName(String uid) async {
    final snap = await _accounts.doc(uid).get();
    return lastNameFrom(snap.data());
  }

  Future<void> saveLastName(String uid, String lastName) {
    return _accounts.doc(uid).update({
      'lastName': PersonNameValidator.normalize(lastName),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The owner's private date of birth. Like the surname it lives on
  /// `users/{uid}`: other members see the age the server derives from it on
  /// `profiles/{uid}`, never the date.
  Future<DateTime?> fetchBirthDate(String uid) async {
    final snap = await _accounts.doc(uid).get();
    return birthDateFrom(snap.data());
  }

  /// Set once: the rules refuse a different date afterwards.
  Future<void> saveBirthDate(String uid, DateTime birthDate) {
    return _accounts.doc(uid).update({
      'birthDate': Timestamp.fromDate(birthDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static DateTime? birthDateFrom(Map<String, dynamic>? account) {
    final value = account?['birthDate'];
    return value is Timestamp ? value.toDate() : null;
  }

  static String? lastNameFrom(Map<String, dynamic>? account) {
    final value = account?['lastName'];
    if (value is! String) {
      return null;
    }
    final lastName = PersonNameValidator.normalize(value);
    return lastName.isEmpty ? null : lastName;
  }

  Future<UserPreferences> fetchPreferences(String uid) async {
    final snap = await _preferences.doc(uid).get();
    return _preferencesFrom(uid, snap.data() ?? const {});
  }

  Future<void> savePreferences(UserPreferences preferences) {
    return _preferences.doc(preferences.uid).set({
      'preferredGender': preferences.preferredGender,
      'minAge': preferences.minAge,
      'maxAge': preferences.maxAge,
      'maxDistance': preferences.maxDistance,
      'relationshipGoals': preferences.relationshipGoals,
      'interests': preferences.interests,
      'showMe': preferences.showMe,
      'discoveryEnabled': preferences.discoveryEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Discovery is a Cloud Function so clients never query thousands of
  /// profiles or read `userLocation`.
  Future<Page<DiscoveryCard>> loadDiscoveryPage({
    String? cursor,
    int limit = 10,
  }) async {
    final backend = _backend;
    if (backend == null) {
      return const Page(items: []);
    }
    final data = await backend.invoke('getDiscoveryFeed', {
      'cursor': cursor,
      'limit': limit,
    });
    final rawItems = data['items'];
    final items = <DiscoveryCard>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          items.add(_cardFrom(Map<String, dynamic>.from(item)));
        }
      }
    }
    return Page(
      items: items,
      nextCursor: data['nextCursor'] as String?,
    );
  }

  UserProfile _profileFrom(String uid, Map<String, dynamic> data) {
    // Only a profile written before the date moved to the account still has
    // one here; the owner's is read with [fetchBirthDate].
    final birthDate = firestoreDate(data['birthDate']);
    return UserProfile(
      uid: uid,
      displayName: (data['displayName'] as String?) ?? '',
      birthDate: birthDate,
      age: firestoreInt(data['age'], 0) == 0
          ? _ageFrom(birthDate)
          : firestoreInt(data['age'], 0),
      gender: data['gender'] as String?,
      interestedIn: data['interestedIn'] as String?,
      bio: data['bio'] as String?,
      photos: _photosFrom(data['photos']),
      interests: firestoreStringList(data['interests']),
      relationshipGoal: data['relationshipGoal'] as String?,
      occupation: data['occupation'] as String?,
      education: data['education'] as String?,
      languages: firestoreStringList(data['languages']),
      hobbies: firestoreStringList(data['hobbies']),
      heightCm: firestoreInt(data['heightCm'], 0) == 0
          ? null
          : firestoreInt(data['heightCm'], 0),
      city: data['city'] as String?,
      lifestyle: firestoreStringList(data['lifestyle']),
      lifestyleProfile: ProfileLifestyle.fromMap(
        data['lifestyleProfile'] ?? data['lifestyle'],
      ),
      onboardingStep: OnboardingStep.fromStorage(data['onboardingStep']),
      profileCompleted: firestoreFlag(data['profileCompleted']),
      onboardingCompleted: firestoreFlag(data['onboardingCompleted']),
      isProfileComplete: firestoreFlag(data['isProfileComplete']) ||
          firestoreFlag(data['profileCompleted']) ||
          firestoreFlag(data['onboardingCompleted']),
      isDiscoverable: firestoreFlag(data['isDiscoverable']),
      createdAt: firestoreDate(data['createdAt']),
      updatedAt: firestoreDate(data['updatedAt']),
    );
  }

  /// Everything this client writes to the member-readable `profiles/{uid}`.
  /// `displayName` is the first name only; the surname is saved separately
  /// through [saveLastName] and must never be added here. Neither must the
  /// date of birth ([saveBirthDate]) — nor the age, which the server writes.
  static Map<String, dynamic> publicProfileMap(UserProfile profile) {
    return {
      'uid': profile.uid,
      'displayName': profile.displayName,
      'gender': profile.gender,
      'interestedIn': profile.interestedIn,
      'bio': profile.bio,
      'photos': [
        for (final photo in _sortedPhotos(profile.photos))
          {
            'id': photo.id,
            'storagePath': photo.storagePath,
            'downloadUrl': photo.downloadUrl,
            'thumbUrl': photo.thumbUrl,
            'cardUrl': photo.cardUrl,
            'moderationStatus': photo.moderationStatus,
            'order': photo.order,
            'isPrimary': photo.isPrimary,
            // Round-tripped like cardUrl, and only when true: the server
            // rewrites it from its own ledger on every profile write.
            if (photo.isFaceAnchorVerified) 'faceAnchorVerified': true,
          },
      ],
      'interests': profile.interests,
      'relationshipGoal': profile.relationshipGoal,
      'occupation': profile.occupation,
      'education': profile.education,
      'languages': profile.languages,
      'hobbies': profile.hobbies,
      if (profile.heightCm != null) 'heightCm': profile.heightCm,
      'city': profile.city,
      'lifestyle': profile.lifestyle.isNotEmpty
          ? profile.lifestyle
          : profile.lifestyleProfile.toTags(),
      'lifestyleProfile': profile.lifestyleProfile.toMap(),
      'onboardingStep': profile.onboardingStep.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Exposed for tests: how a stored `photos` array becomes [ProfilePhoto]s.
  @visibleForTesting
  static List<ProfilePhoto> photosFromStored(Object? value) => _photosFrom(value);

  static List<ProfilePhoto> _photosFrom(Object? value) {
    if (value is! List) {
      return const [];
    }
    final photos = [
      for (var i = 0; i < value.length; i++)
        if (value[i] is Map)
          ProfilePhoto(
            id: ((value[i] as Map)['id'] as String?) ?? '',
            storagePath: ((value[i] as Map)['storagePath'] as String?) ?? '',
            downloadUrl: (value[i] as Map)['downloadUrl'] as String?,
            thumbUrl: (value[i] as Map)['thumbUrl'] as String?,
            cardUrl: (value[i] as Map)['cardUrl'] as String?,
            moderationStatus:
                ((value[i] as Map)['moderationStatus'] as String?) ?? 'pending',
            order: firestoreInt((value[i] as Map)['order'], i),
            isPrimary: (value[i] as Map)['isPrimary'] as bool? ?? i == 0,
            // Absent on every photo written before Face Anchor existed, and
            // absent means not verified. Only the exact boolean counts.
            isFaceAnchorVerified:
                (value[i] as Map)['faceAnchorVerified'] == true,
          )
        else if (value[i] is String)
          ProfilePhoto(
            id: value[i] as String,
            storagePath: value[i] as String,
            downloadUrl: value[i] as String,
            order: i,
            isPrimary: i == 0,
          ),
    ];
    return _sortedPhotos(photos);
  }

  static List<ProfilePhoto> _sortedPhotos(List<ProfilePhoto> photos) {
    final copy = [...photos]..sort((a, b) => a.order.compareTo(b.order));
    return copy;
  }

  UserPreferences _preferencesFrom(String uid, Map<String, dynamic> data) {
    return UserPreferences(
      uid: uid,
      preferredGender: data['preferredGender'] as String?,
      minAge: firestoreInt(data['minAge'], 18),
      maxAge: firestoreInt(data['maxAge'], 99),
      maxDistance: firestoreInt(data['maxDistance'], 50),
      relationshipGoals: firestoreStringList(data['relationshipGoals']),
      interests: firestoreStringList(data['interests']),
      showMe: data['showMe'] as String?,
      discoveryEnabled: data['discoveryEnabled'] as bool? ?? true,
    );
  }

  DiscoveryCard _cardFrom(Map<String, dynamic> data) {
    final profileData = data['profile'];
    final profile = profileData is Map
        ? _profileFrom(
            (profileData['uid'] as String?) ?? '',
            Map<String, dynamic>.from(profileData),
          )
        : UserProfile(
            uid: (data['uid'] as String?) ?? '',
            displayName: (data['displayName'] as String?) ?? '',
          );
    return DiscoveryCard(
      profile: profile,
      distanceLabel: data['distanceLabel'] as String?,
      compatibilityScore: firestoreInt(data['compatibilityScore'], 0),
      sharedInterests: firestoreStringList(data['sharedInterests']),
      compatibilityReasons: firestoreStringList(data['compatibilityReasons']),
    );
  }

  static int? _ageFrom(DateTime? birthDate) {
    if (birthDate == null) {
      return null;
    }
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }
}
