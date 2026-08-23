import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';

void main() {
  group('profile verification status', () {
    test('maps firestore values', () {
      expect(
        profileVerificationStatusFromFirestore('approved'),
        ProfileVerificationStatus.approved,
      );
      expect(
        profileVerificationStatusFromFirestore('retry_required'),
        ProfileVerificationStatus.retryRequired,
      );
      expect(
        profileVerificationStatusFromFirestore(null),
        ProfileVerificationStatus.notStarted,
      );
    });

    test('canStart excludes pending and approved', () {
      expect(ProfileVerificationStatus.notStarted.canStart, isTrue);
      expect(ProfileVerificationStatus.pending.canStart, isFalse);
      expect(ProfileVerificationStatus.approved.canStart, isFalse);
      expect(ProfileVerificationStatus.retryRequired.canStart, isTrue);
    });

    test('serializes to firestore strings', () {
      expect(
        profileVerificationStatusToFirestore(ProfileVerificationStatus.pending),
        'pending',
      );
    });
  });
}
