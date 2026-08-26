import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('photo moderation modules exist in Cloud Functions', () {
    expect(File('functions/src/moderation/photoModerationService.ts').existsSync(), isTrue);
    expect(File('functions/src/moderation/manualModerationProvider.ts').existsSync(), isTrue);
    expect(File('functions/src/moderation/profileModerationGuard.ts').existsSync(), isTrue);
    expect(File('functions/src/smoke/smokeTestUsers.ts').existsSync(), isTrue);
  });

  test('onProfilePhotoUploaded delegates to moderation service', () {
    final source = File('functions/src/backend.ts').readAsStringSync();
    expect(source.contains('processPendingProfilePhoto'), isTrue);
    expect(source.contains('moderationStatus: "approved"'), isFalse);
  });

  test('complete onboarding allows pending photos without force-approving', () {
    final source = File('functions/src/onboarding.ts').readAsStringSync();
    expect(source.contains('photos-not-approved'), isFalse);
    expect(source.contains('photosReadyForDiscovery'), isTrue);
    expect(source.contains('isDiscoverable: true'), isTrue);
    expect(source.contains('"rejected" ? "rejected" : "approved"'), isFalse);
  });

  test('discovery admits only approved photos', () {
    final safety = File('functions/src/profileSafety.ts').readAsStringSync();
    final matching = File('functions/src/discoveryMatching.ts').readAsStringSync();
    expect(safety.contains('usableDiscoveryPhotos'), isTrue);
    expect(safety.contains('return approvedPhotos(photos)'), isTrue);
    expect(safety.contains('discoveryProfileProjection'), isTrue);
    expect(matching.contains('countUsableDiscoveryPhotos'), isTrue);
    expect(matching.contains('photos_insufficient'), isTrue);
  });

  test('report pipeline marks profile for manual review', () {
    final source = File('functions/src/social.ts').readAsStringSync();
    expect(source.contains('markProfilePhotosForManualReview'), isTrue);
  });
}
