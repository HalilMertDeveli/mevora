import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';

/// Dev/test discovery profiles. Never written to production Firestore.
class MockDiscoveryProfile {
  const MockDiscoveryProfile({
    required this.profile,
    required this.compatibilityScore,
    required this.sharedInterests,
    required this.compatibilityReasons,
    this.distanceKm,
    this.distanceLabel,
    this.likesYou = false,
  });

  final UserProfile profile;
  final int compatibilityScore;
  final List<String> sharedInterests;
  final List<String> compatibilityReasons;
  final double? distanceKm;
  final String? distanceLabel;

  /// When true, a Like/Super Like from the current user creates a demo match.
  final bool likesYou;

  String get uid => profile.uid;

  MockDiscoveryProfile withLastActiveAt(DateTime? lastActiveAt) {
    return MockDiscoveryProfile(
      profile: UserProfile(
        uid: profile.uid,
        displayName: profile.displayName,
        birthDate: profile.birthDate,
        age: profile.age,
        gender: profile.gender,
        interestedIn: profile.interestedIn,
        bio: profile.bio,
        photos: profile.photos,
        interests: profile.interests,
        relationshipGoal: profile.relationshipGoal,
        occupation: profile.occupation,
        education: profile.education,
        languages: profile.languages,
        city: profile.city,
        lifestyle: profile.lifestyle,
        lifestyleProfile: profile.lifestyleProfile,
        onboardingStep: profile.onboardingStep,
        lastActiveAt: lastActiveAt,
        profileCompleted: profile.profileCompleted,
        onboardingCompleted: profile.onboardingCompleted,
        isProfileComplete: profile.isProfileComplete,
        isDiscoverable: profile.isDiscoverable,
        createdAt: profile.createdAt,
        updatedAt: profile.updatedAt,
      ),
      compatibilityScore: compatibilityScore,
      sharedInterests: sharedInterests,
      compatibilityReasons: compatibilityReasons,
      distanceKm: distanceKm,
      distanceLabel: distanceLabel,
      likesYou: likesYou,
    );
  }
}

/// Bundled Unsplash portraits for demo decks. Never written to Firestore.
abstract final class MockDiscoveryPhotos {
  static List<String> forProfile(String uid, {int count = 1}) {
    final asset =
        MevoraPhotoImages.portraitForUid(uid) ??
        MevoraPhotoImages.portraits.values.first;
    return List<String>.filled(count, asset);
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
        bio: 'Müze haftasonları, iyi kahve ve deniz kenarında uzun yürüyüşler.',
        interests: const ['art', 'coffee', 'travel', 'yoga'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['early-riser', 'city-explorer'],
        score: 88,
        shared: const ['travel', 'coffee'],
        reasons: const [
          'İkiniz de seyahati seviyorsunuz',
          'Kahve kültürü ortak ilginiz',
          'Benzer ilişki amacı',
        ],
        distanceKm: 2.4,
        photos: 3,
        likesYou: true,
      ),
      _entry(
        uid: 'mock-02',
        name: 'Deniz',
        age: 29,
        city: 'Ankara',
        gender: 'man',
        bio: 'Ürün tasarımcısı. Fazla yemek yapar, metroda kitap okur.',
        interests: const ['design', 'cooking', 'music', 'hiking'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['foodie'],
        score: 76,
        shared: const ['music'],
        reasons: const [
          'İlişki amaçlarınız uyumlu',
          'Canlı müziği ikiniz de seviyorsunuz',
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
        bio:
            'Koşucu, bitki bakıcısı ve bir sonraki sahil kaçamaklarının peşinde.',
        interests: const ['running', 'plants', 'travel', 'photography'],
        relationshipGoal: 'casual',
        lifestyle: const ['active', 'outdoors'],
        score: 71,
        shared: const ['travel', 'photography'],
        reasons: const ['Ortak fotoğraf tutkusu', 'Aktif yaşam tarzı uyumu'],
        distanceKm: 12.0,
        photos: 3,
      ),
      _entry(
        uid: 'mock-04',
        name: 'Can',
        age: 31,
        city: 'Istanbul',
        gender: 'man',
        bio: 'Girişim mühendisi. Kutu oyunları, caz barları ve sakin pazarlar.',
        interests: const ['tech', 'jazz', 'board-games', 'wine'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['night-owl'],
        score: 82,
        shared: const ['board-games'],
        reasons: const [
          'İkiniz de uzun vadeli bağ arıyorsunuz',
          'Kutu oyunu geceleri ortak',
        ],
        distanceKm: 4.7,
        photos: 2,
        likesYou: true,
      ),
      _entry(
        uid: 'mock-05',
        name: 'Aylin',
        age: 27,
        city: 'Bursa',
        gender: 'woman',
        bio: 'Gündüz öğretmen, akşamları seramik.',
        interests: const ['pottery', 'books', 'tea', 'volunteering'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['creative'],
        score: 69,
        shared: const ['books'],
        reasons: const [
          'İkiniz de okumayı seviyorsunuz',
          'Yaratıcı hobiler ortak',
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
        bio:
            'Yelken eğitmeni. Gün batımı, deniz mahsulleri ve plansız yolculuklar.',
        interests: const ['sailing', 'seafood', 'travel', 'fitness'],
        relationshipGoal: 'casual',
        lifestyle: const ['outdoors', 'active'],
        score: 64,
        shared: const ['fitness'],
        reasons: const [
          'Aktif yaşam tarzı örtüşmesi',
          'İkiniz de maceraya açığınız',
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
        bio:
            'Sinema öğrencisi. Bağımsız salonlar, plak dükkanları ve teras sohbetleri.',
        interests: const ['film', 'vinyl', 'coffee', 'writing'],
        relationshipGoal: 'figuringOut',
        lifestyle: const ['creative', 'night-owl'],
        score: 91,
        shared: const ['coffee', 'film'],
        reasons: const [
          'Güçlü ortak film ilgisi',
          'Özel kahveyi ikiniz de seviyorsunuz',
          'Yaratıcı enerji uyumu',
        ],
        distanceKm: 1.8,
        photos: 3,
        likesYou: true,
      ),
      _entry(
        uid: 'mock-08',
        name: 'Burak',
        age: 28,
        city: 'Eskisehir',
        gender: 'man',
        bio: 'Mimar. Şehirleri çizer, iyi ekmeğin peşinden gider.',
        interests: const ['architecture', 'baking', 'cycling', 'history'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['early-riser'],
        score: 73,
        shared: const ['cycling'],
        reasons: const [
          'Benzer sabah rutini',
          'İkiniz de bisikleti seviyorsunuz',
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
        bio:
            'Pazarlama yöneticisi. Ne randevu gecesini ne de iyi bir çalma listesini kaçırır.',
        interests: const ['music', 'food', 'travel', 'podcasts'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['social', 'foodie'],
        score: 85,
        shared: const ['travel', 'music', 'food'],
        reasons: const [
          'Üç ortak ilgi alanı',
          'İlişki amaçlarınız uyumlu',
          'Benzer sosyal enerji',
        ],
        distanceKm: 3.2,
        photos: 3,
        likesYou: true,
      ),
      _entry(
        uid: 'mock-10',
        name: 'Kerem',
        age: 34,
        city: 'Izmir',
        gender: 'man',
        bio: 'Şef. Tarif dener, her masadan bir hikâye toplar.',
        interests: const ['cooking', 'wine', 'travel', 'photography'],
        relationshipGoal: 'longTerm',
        lifestyle: const ['foodie', 'night-owl'],
        score: 61,
        shared: const ['travel'],
        reasons: const ['Ortak gezme tutkusu', 'Tamamlayıcı yaşam tarzları'],
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
    bool likesYou = false,
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
      likesYou: likesYou,
    );
  }
}
