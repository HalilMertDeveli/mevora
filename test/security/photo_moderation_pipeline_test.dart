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

  test('complete onboarding no longer force-approves pending photos', () {
    final source = File('functions/src/onboarding.ts').readAsStringSync();
    expect(source.contains('photos-not-approved'), isTrue);
    expect(source.contains('"rejected" ? "rejected" : "approved"'), isFalse);
  });

  test('report pipeline marks profile for manual review', () {
    final source = File('functions/src/social.ts').readAsStringSync();
    expect(source.contains('markProfilePhotosForManualReview'), isTrue);
  });
}
