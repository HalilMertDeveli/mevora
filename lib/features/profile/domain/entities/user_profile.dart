import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';

class ProfilePhoto {
  const ProfilePhoto({
    required this.id,
    required this.storagePath,
    this.downloadUrl,
    this.thumbUrl,
    this.moderationStatus = 'pending',
    this.order = 0,
    this.isPrimary = false,
  });

  final String id;
  final String storagePath;
  final String? downloadUrl;
  final String? thumbUrl;

  /// `pending` | `approved` | `rejected`. Clients cannot mark approved.
  final String moderationStatus;

  /// Display order in profile. Lower values appear first.
  final int order;

  /// Primary photo shown on cards. Exactly one photo should be primary.
  final bool isPrimary;

  bool get isPublic => moderationStatus == 'approved';

  ProfilePhoto copyWith({
    String? id,
    String? storagePath,
    String? downloadUrl,
    String? thumbUrl,
    String? moderationStatus,
    int? order,
    bool? isPrimary,
  }) {
    return ProfilePhoto(
      id: id ?? this.id,
      storagePath: storagePath ?? this.storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      order: order ?? this.order,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
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
    this.interestedIn,
    this.bio,
    this.photos = const [],
    this.interests = const [],
    this.relationshipGoal,
    this.occupation,
    this.education,
    this.languages = const [],
    this.city,
    this.lifestyle = const [],
    this.lifestyleProfile = const ProfileLifestyle(),
    this.onboardingStep = OnboardingStep.basicInfo,
    this.lastActiveAt,
    this.profileCompleted = false,
    this.onboardingCompleted = false,
    this.isProfileComplete = false,
    this.isDiscoverable = false,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final DateTime? birthDate;
  final int? age;
  final String? gender;
  final String? interestedIn;
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
  final ProfileLifestyle lifestyleProfile;
  final OnboardingStep onboardingStep;
  final DateTime? lastActiveAt;
  final bool profileCompleted;
  final bool onboardingCompleted;

  /// Public completion flag used by discovery gating.
  final bool isProfileComplete;
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
    String? interestedIn,
    String? bio,
    List<ProfilePhoto>? photos,
    List<String>? interests,
    String? relationshipGoal,
    String? occupation,
    String? education,
    List<String>? languages,
    String? city,
    List<String>? lifestyle,
    ProfileLifestyle? lifestyleProfile,
    OnboardingStep? onboardingStep,
    DateTime? lastActiveAt,
    bool? profileCompleted,
    bool? onboardingCompleted,
    bool? isProfileComplete,
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
      interestedIn: interestedIn ?? this.interestedIn,
      bio: bio ?? this.bio,
      photos: photos ?? this.photos,
      interests: interests ?? this.interests,
      relationshipGoal: relationshipGoal ?? this.relationshipGoal,
      occupation: occupation ?? this.occupation,
      education: education ?? this.education,
      languages: languages ?? this.languages,
      city: city ?? this.city,
      lifestyle: lifestyle ?? this.lifestyle,
      lifestyleProfile: lifestyleProfile ?? this.lifestyleProfile,
      onboardingStep: onboardingStep ?? this.onboardingStep,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
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
