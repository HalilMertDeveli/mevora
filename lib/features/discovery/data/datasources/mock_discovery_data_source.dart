import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Dev/test discovery profiles. Never written to production Firestore.
class MockDiscoveryProfile {
  const MockDiscoveryProfile({
    required this.profile,
    required this.compatibilityScore,
    required this.sharedInterests,
    required this.compatibilityReasons,
    this.distanceKm,
    this.distanceLabel,
  });

  final UserProfile profile;
  final int compatibilityScore;
  final List<String> sharedInterests;
  final List<String> compatibilityReasons;
  final double? distanceKm;
  final String? distanceLabel;

  String get uid => profile.uid;
}

/// Illustration-style avatar seeds for dev UI. Cards render placeholders locally.
abstract final class MockDiscoveryPhotos {
  static List<String> forProfile(String uid, {int count = 1}) {
    return List<String>.generate(count, (index) => 'mock://$uid/$index');
  }
}

abstract final class MockDiscoveryDataSource {
  static const int profileCount = 10;

  static List<MockDiscoveryProfile> profiles({String? excludeUid}) {
    final all = _buildProfiles();
    if (excludeUid == null) {
      return all;
    }
    return all.where((profile) => profile.uid != excludeUid).toList();
  }

  static List<MockDiscoveryProfile> _buildProfiles() {
    return [
      _entry(
        uid: 'mock-01',
        name: 'Elif',
        age: 26,
        city: 'Istanbul',
        gender: 'woman',
        bio: 'Museum weekends, strong coffee, and long walks by the water.',
        interests: const ['art', 'coffee', 'travel', 'yoga'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['early-riser', 'city-explorer'],
        score: 88,
        shared: const ['travel', 'coffee'],
        reasons: const [
          'You both love travel',
          'Shared interest in coffee culture',
          'Similar relationship goals',
        ],
        distanceKm: 2.4,
        photos: 3,
      ),
      _entry(
        uid: 'mock-02',
        name: 'Deniz',
        age: 29,
        city: 'Ankara',
        gender: 'man',
        bio: 'Product designer who cooks too much and reads on the metro.',
        interests: const ['design', 'cooking', 'music', 'hiking'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['foodie'],
        score: 76,
        shared: const ['music'],
        reasons: const [
          'Aligned relationship goals',
          'Both enjoy live music',
        ],
        distanceKm: 8.1,
        photos: 2,
      ),
      _entry(
        uid: 'mock-03',
        name: 'Zeynep',
        age: 24,
        city: 'Izmir',
        gender: 'woman',
        bio: 'Runner, plant parent, and always planning the next coastal trip.',
        interests: const ['running', 'plants', 'travel', 'photography'],
        relationshipGoal: 'casual',
        lifestyle: const ['active', 'outdoors'],
        score: 71,
        shared: const ['travel', 'photography'],
        reasons: const [
          'Shared love of photography',
          'Active lifestyle match',
        ],
        distanceKm: 12.0,
        photos: 3,
      ),
      _entry(
        uid: 'mock-04',
        name: 'Can',
        age: 31,
        city: 'Istanbul',
        gender: 'man',
        bio: 'Startup engineer. Board games, jazz bars, and quiet Sundays.',
        interests: const ['tech', 'jazz', 'board-games', 'wine'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['night-owl'],
        score: 82,
        shared: const ['board-games'],
        reasons: const [
          'Both value long-term connection',
          'Shared board-game nights',
        ],
        distanceKm: 4.7,
        photos: 2,
      ),
      _entry(
        uid: 'mock-05',
        name: 'Aylin',
        age: 27,
        city: 'Bursa',
        gender: 'woman',
        bio: 'Teacher by day, pottery enthusiast by evening.',
        interests: const ['pottery', 'books', 'tea', 'volunteering'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['creative'],
        score: 69,
        shared: const ['books'],
        reasons: const [
          'You both enjoy reading',
          'Creative hobbies in common',
        ],
        distanceKm: 18.3,
        photos: 2,
      ),
      _entry(
        uid: 'mock-06',
        name: 'Mert',
        age: 33,
        city: 'Antalya',
        gender: 'man',
        bio: 'Sailing instructor. Sunsets, seafood, and spontaneous road trips.',
        interests: const ['sailing', 'seafood', 'travel', 'fitness'],
        relationshipGoal: 'casual',
        lifestyle: const ['outdoors', 'active'],
        score: 64,
        shared: const ['fitness'],
        reasons: const [
          'Active lifestyle overlap',
          'Both open to adventure',
        ],
        distanceKm: 22.5,
        photos: 3,
      ),
      _entry(
        uid: 'mock-07',
        name: 'Selin',
        age: 25,
        city: 'Istanbul',
        gender: 'woman',
        bio: 'Film student. Indie cinemas, vinyl shops, and rooftop conversations.',
        interests: const ['film', 'vinyl', 'coffee', 'writing'],
        relationshipGoal: 'figuringOut',
        lifestyle: const ['creative', 'night-owl'],
        score: 91,
        shared: const ['coffee', 'film'],
        reasons: const [
          'Strong shared interests in film',
          'Both love specialty coffee',
          'Creative energy match',
        ],
        distanceKm: 1.8,
        photos: 3,
      ),
      _entry(
        uid: 'mock-08',
        name: 'Burak',
        age: 28,
        city: 'Eskisehir',
        gender: 'man',
        bio: 'Architect sketching cities and chasing good bread wherever I go.',
        interests: const ['architecture', 'baking', 'cycling', 'history'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['early-riser'],
        score: 73,
        shared: const ['cycling'],
        reasons: const [
          'Similar morning routine',
          'Both enjoy cycling',
        ],
        distanceKm: 15.0,
        photos: 2,
      ),
      _entry(
        uid: 'mock-09',
        name: 'Ece',
        age: 30,
        city: 'Istanbul',
        gender: 'woman',
        bio: 'Marketing lead who never skips date night or a good playlist.',
        interests: const ['music', 'food', 'travel', 'podcasts'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['social', 'foodie'],
        score: 85,
        shared: const ['travel', 'music', 'food'],
        reasons: const [
          'Three shared interests',
          'Relationship goals align',
          'Similar social energy',
        ],
        distanceKm: 3.2,
        photos: 3,
      ),
      _entry(
        uid: 'mock-10',
        name: 'Kerem',
        age: 34,
        city: 'Izmir',
        gender: 'man',
        bio: 'Chef testing recipes and collecting stories from every table.',
        interests: const ['cooking', 'wine', 'travel', 'photography'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['foodie', 'night-owl'],
        score: 61,
        shared: const ['travel'],
        reasons: const [
          'Shared wanderlust',
          'Complementary lifestyles',
        ],
        distanceKm: 28.0,
        photos: 2,
      ),
    ];
  }

  static MockDiscoveryProfile _entry({
    required String uid,
    required String name,
    required int age,
    required String city,
    required String gender,
    required String bio,
    required List<String> interests,
    required String relationshipGoal,
    required List<String> lifestyle,
    required int score,
    required List<String> shared,
    required List<String> reasons,
    required double distanceKm,
    required int photos,
  }) {
    final photoUrls = MockDiscoveryPhotos.forProfile(uid, count: photos);
    return MockDiscoveryProfile(
      profile: UserProfile(
        uid: uid,
        displayName: name,
        age: age,
        gender: gender,
        bio: bio,
        city: city,
        interests: interests,
        relationshipGoal: relationshipGoal,
        lifestyle: lifestyle,
        photos: [
          for (var i = 0; i < photoUrls.length; i++)
            ProfilePhoto(
              id: '$uid-photo-$i',
              storagePath: 'mock/$uid/$i.jpg',
              downloadUrl: photoUrls[i],
              moderationStatus: 'approved',
            ),
        ],
        isDiscoverable: true,
        profileCompleted: true,
        onboardingCompleted: true,
      ),
      compatibilityScore: score,
      sharedInterests: shared,
      compatibilityReasons: reasons,
      distanceKm: distanceKm,
      distanceLabel: '${distanceKm.toStringAsFixed(1)} km away',
    );
  }
}
