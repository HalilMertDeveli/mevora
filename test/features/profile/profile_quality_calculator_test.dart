import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/services/profile_quality_calculator.dart';

void main() {
  test('3 photos raise quality vs fewer photos', () {
    const withThree = UserProfile(
      uid: 'a',
      displayName: 'Ada',
      age: 27,
      bio: 'Love hiking and coffee chats',
      city: 'Istanbul',
      relationshipGoal: 'longTerm',
      profileCompleted: true,
      photos: [
        ProfilePhoto(id: '1', storagePath: 'a', moderationStatus: 'approved'),
        ProfilePhoto(id: '2', storagePath: 'b', moderationStatus: 'approved'),
        ProfilePhoto(id: '3', storagePath: 'c', moderationStatus: 'approved'),
      ],
    );
    const withOne = UserProfile(
      uid: 'b',
      displayName: 'Ada',
      age: 27,
      bio: 'Love hiking and coffee chats',
      city: 'Istanbul',
      relationshipGoal: 'longTerm',
      profileCompleted: true,
      photos: [
        ProfilePhoto(id: '1', storagePath: 'a', moderationStatus: 'approved'),
      ],
    );

    final high = ProfileQualityCalculator.calculate(
      profile: withThree,
      personalityAnswerCount: 3,
    );
    final low = ProfileQualityCalculator.calculate(
      profile: withOne,
      personalityAnswerCount: 3,
    );
    expect(high.score, greaterThan(low.score));
    expect(high.missingFieldKeys, isNot(contains('photos')));
    expect(low.missingFieldKeys, contains('photos'));
  });

  test('Spotify is optional bonus and never listed as missing', () {
    const profile = UserProfile(
      uid: 'a',
      displayName: 'Ada',
      age: 27,
      bio: 'Hello world!!',
      city: 'Ankara',
      relationshipGoal: 'longTerm',
      profileCompleted: true,
      photos: [
        ProfilePhoto(id: '1', storagePath: 'a', moderationStatus: 'approved'),
        ProfilePhoto(id: '2', storagePath: 'b', moderationStatus: 'approved'),
        ProfilePhoto(id: '3', storagePath: 'c', moderationStatus: 'approved'),
      ],
    );
    final without = ProfileQualityCalculator.calculate(
      profile: profile,
      personalityAnswerCount: 3,
      spotifyConnected: false,
    );
    final withSpotify = ProfileQualityCalculator.calculate(
      profile: profile,
      personalityAnswerCount: 3,
      spotifyConnected: true,
    );
    expect(withSpotify.score, greaterThanOrEqualTo(without.score));
    expect(without.missingFieldKeys, isNot(contains('spotify')));
    expect(without.score, greaterThanOrEqualTo(ProfileQualityCalculator.floor));
  });

  test('sparse profiles keep a floor score', () {
    const sparse = UserProfile(uid: 'x', displayName: 'X');
    final result = ProfileQualityCalculator.calculate(profile: sparse);
    expect(result.score, ProfileQualityCalculator.floor);
    expect(result.missingFieldKeys, contains('photos'));
    expect(result.missingFieldKeys, contains('bio'));
    expect(result.missingFieldKeys, contains('personality'));
  });
}
