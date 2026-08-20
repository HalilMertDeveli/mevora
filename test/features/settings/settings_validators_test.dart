import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/settings/domain/validators/discovery_prefs_validator.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/validators/password_validator.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/features/settings/domain/validators/profile_edit_validator.dart';

void main() {
  group('PasswordValidator', () {
    test('accepts valid change', () {
      expect(
        PasswordValidator.isValidChange(
          current: 'old-pass-1',
          newPassword: 'new-pass-1',
          confirm: 'new-pass-1',
        ),
        isTrue,
      );
    });

    test('rejects short password', () {
      expect(PasswordValidator.validateNew('short'), 'password_too_short');
    });
  });

  group('PhotoPolicy', () {
    final photos = [
      const ProfilePhoto(id: '1', storagePath: 'a', isPrimary: true, order: 0),
      const ProfilePhoto(id: '2', storagePath: 'b', order: 1),
      const ProfilePhoto(id: '3', storagePath: 'c', order: 2),
    ];

    test('blocks delete below minimum', () {
      expect(PhotoPolicy.canDelete(photos, '1'), isFalse);
      expect(PhotoPolicy.deleteBlockReason(photos, '1'), isNotNull);
    });

    test('blocks deleting primary without replacement', () {
      final four = [
        ...photos,
        const ProfilePhoto(id: '4', storagePath: 'd', order: 3),
      ];
      expect(PhotoPolicy.deleteBlockReason(four, '1'), 'photo_primary_delete_blocked');
    });

    test('sets primary photo', () {
      final updated = PhotoPolicy.setPrimary(photos, '2');
      expect(updated.firstWhere((p) => p.id == '2').isPrimary, isTrue);
    });
  });

  group('ProfileEditValidator', () {
    test('requires primary photo', () {
      const profile = UserProfile(
        uid: 'u1',
        displayName: 'Ada',
        photos: [
          ProfilePhoto(id: '1', storagePath: 'a', order: 0),
          ProfilePhoto(id: '2', storagePath: 'b', order: 1),
          ProfilePhoto(id: '3', storagePath: 'c', order: 2),
        ],
      );
      expect(ProfileEditValidator.validateProfile(profile), 'photo_primary_required');
    });
  });

  group('DiscoveryPrefsValidator', () {
    test('rejects invalid age range', () {
      const prefs = UserPreferences(uid: 'u1', minAge: 30, maxAge: 25);
      expect(DiscoveryPrefsValidator.validate(prefs), 'age_range_invalid');
    });
  });
}
