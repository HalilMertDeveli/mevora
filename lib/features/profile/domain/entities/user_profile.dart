class ProfilePhoto {
  const ProfilePhoto({
    required this.id,
    required this.storagePath,
    this.downloadUrl,
    this.thumbUrl,
    this.moderationStatus = 'pending',
  });

  final String id;
  final String storagePath;
  final String? downloadUrl;
  final String? thumbUrl;

  /// `pending` | `approved` | `rejected`. Clients cannot mark approved.
  final String moderationStatus;

  bool get isPublic => moderationStatus == 'approved';
}

/// Public dating projection. Never includes password, phone, private email,
/// GPS, FCM tokens, or account providers.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.birthDate,
    this.age,
    this.gender,
    this.bio,
    this.photos = const [],
    this.interests = const [],
    this.relationshipGoal,
    this.occupation,
    this.education,
    this.languages = const [],
    this.city,
    this.lifestyle = const [],
    this.lastActiveAt,
    this.profileCompleted = false,
    this.onboardingCompleted = false,
    this.isDiscoverable = false,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final DateTime? birthDate;
  final int? age;
  final String? gender;
  final String? bio;
  final List<ProfilePhoto> photos;
  final List<String> interests;
  final String? relationshipGoal;
  final String? occupation;
  final String? education;
  final List<String> languages;

  /// City label only. Never lat/lng.
  final String? city;
  final List<String> lifestyle;
  final DateTime? lastActiveAt;
  final bool profileCompleted;
  final bool onboardingCompleted;
  final bool isDiscoverable;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get resolvedAge {
    if (age != null) {
      return age!;
    }
    final birth = birthDate;
    if (birth == null) {
      return 0;
    }
    final today = DateTime.now();
    var years = today.year - birth.year;
    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) {
      years -= 1;
    }
    return years;
  }

  UserProfile copyWith({
    String? uid,
    String? displayName,
    DateTime? birthDate,
    int? age,
    String? gender,
    String? bio,
    List<ProfilePhoto>? photos,
    List<String>? interests,
    String? relationshipGoal,
    String? occupation,
    String? education,
    List<String>? languages,
    String? city,
    List<String>? lifestyle,
    DateTime? lastActiveAt,
    bool? profileCompleted,
    bool? onboardingCompleted,
    bool? isDiscoverable,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      birthDate: birthDate ?? this.birthDate,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      photos: photos ?? this.photos,
      interests: interests ?? this.interests,
      relationshipGoal: relationshipGoal ?? this.relationshipGoal,
      occupation: occupation ?? this.occupation,
      education: education ?? this.education,
      languages: languages ?? this.languages,
      city: city ?? this.city,
      lifestyle: lifestyle ?? this.lifestyle,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      isDiscoverable: isDiscoverable ?? this.isDiscoverable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class UserPreferences {
  const UserPreferences({
    required this.uid,
    this.preferredGender,
    this.minAge = 18,
    this.maxAge = 99,
    this.maxDistance = 50,
    this.relationshipGoals = const [],
    this.interests = const [],
    this.showMe,
    this.discoveryEnabled = true,
  });

  final String uid;
  final String? preferredGender;
  final int minAge;
  final int maxAge;
  final int maxDistance;
  final List<String> relationshipGoals;
  final List<String> interests;
  final String? showMe;
  final bool discoveryEnabled;
}

class DiscoveryCard {
  const DiscoveryCard({
    required this.profile,
    this.distanceLabel,
    this.compatibilityScore,
    this.sharedInterests = const [],
    this.compatibilityReasons = const [],
  });

  final UserProfile profile;

  /// Derived by Cloud Functions. Never raw coordinates.
  final String? distanceLabel;
  final int? compatibilityScore;
  final List<String> sharedInterests;
  final List<String> compatibilityReasons;
}
