import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Profile quality for ranking / UX nudges. Never blocks Discover or Boost.
class ProfileQualityResult {
  const ProfileQualityResult({
    required this.score,
    required this.missingFieldKeys,
    this.factors = const {},
  });

  final int score;
  final List<String> missingFieldKeys;
  final Map<String, double> factors;
}

/// Mirrors `functions/src/recommendation/profileQuality.ts`.
abstract final class ProfileQualityCalculator {
  static const floor = 15;
  static const photoTarget = 3;
  static const personalityTarget = 3;
  static const minBioLength = 8;

  static const weights = <String, double>{
    'photos': 25,
    'bio': 12,
    'age': 8,
    'location': 10,
    'relationshipGoal': 10,
    'personality': 20,
    'completed': 10,
    'activity': 5,
    'spotifyBonus': 5,
  };

  static ProfileQualityResult calculate({
    required UserProfile profile,
    int personalityAnswerCount = 0,
    bool spotifyConnected = false,
    DateTime? now,
  }) {
    final factors = <String, double>{};
    final missing = <String>[];
    final clock = now ?? DateTime.now();

    final photoCount = profile.photos
        .where((photo) => photo.moderationStatus != 'rejected')
        .length;
    factors['photos'] =
        (photoCount / photoTarget).clamp(0.0, 1.0) * weights['photos']!;
    if (photoCount < photoTarget) {
      missing.add('photos');
    }

    final bioFilled = (profile.bio ?? '').trim().length >= minBioLength;
    factors['bio'] = bioFilled ? weights['bio']! : 0;
    if (!bioFilled) {
      missing.add('bio');
    }

    final hasAge = profile.birthDate != null || (profile.age ?? 0) > 0;
    factors['age'] = hasAge ? weights['age']! : 0;

    final hasLocation = (profile.city ?? '').trim().isNotEmpty;
    factors['location'] = hasLocation ? weights['location']! : 0;
    if (!hasLocation) {
      missing.add('location');
    }

    final hasGoal =
        profile.relationshipGoal != null &&
        profile.relationshipGoal!.trim().isNotEmpty;
    factors['relationshipGoal'] = hasGoal ? weights['relationshipGoal']! : 0;
    if (!hasGoal) {
      missing.add('relationshipGoal');
    }

    final answered = personalityAnswerCount < 0 ? 0 : personalityAnswerCount;
    factors['personality'] =
        (answered / personalityTarget).clamp(0.0, 1.0) *
        weights['personality']!;
    if (answered < personalityTarget) {
      missing.add('personality');
    }

    factors['completed'] =
        profile.profileCompleted || profile.isProfileComplete
            ? weights['completed']!
            : 0;

    final lastActive = profile.lastActiveAt;
    if (lastActive == null) {
      factors['activity'] = weights['activity']! * 0.6;
    } else {
      final hours = clock.difference(lastActive).inMinutes / 60.0;
      if (hours <= 24) {
        factors['activity'] = weights['activity']!;
      } else if (hours <= 72) {
        factors['activity'] = weights['activity']! * 0.7;
      } else if (hours <= 14 * 24) {
        factors['activity'] = weights['activity']! * 0.4;
      } else {
        factors['activity'] = weights['activity']! * 0.2;
      }
    }

    // Optional — never added to missingFieldKeys.
    factors['spotifyBonus'] =
        spotifyConnected ? weights['spotifyBonus']! : 0;

    final raw = factors.values.fold<double>(0, (sum, value) => sum + value);
    final score = raw.round().clamp(floor, 100);

    return ProfileQualityResult(
      score: score,
      missingFieldKeys: missing,
      factors: factors,
    );
  }
}
