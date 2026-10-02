import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/onboarding/domain/onboarding_messages.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_data_source.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';

ProfilePhoto _photo(
  String id,
  int order, {
  bool verified = false,
  bool primary = false,
  String status = 'approved',
}) {
  return ProfilePhoto(
    id: id,
    storagePath: 'users/u/profile/photos/$id.jpg',
    order: order,
    isPrimary: primary,
    moderationStatus: status,
    isFaceAnchorVerified: verified,
  );
}

List<String> _ids(List<ProfilePhoto> photos) => [for (final p in photos) p.id];

void main() {
  group('onboarding photo requirement', () {
    test('three ordinary photos and no Face Anchor: blocked', () {
      final photos = [
        _photo('dog', 0, primary: true),
        _photo('trip', 1),
        _photo('car', 2),
      ];
      final result = OnboardingValidators.validatePhotos(
        photos,
        requireFaceAnchor: true,
      );
      expect(
        result.failureOrNull?.message,
        OnboardingMessages.faceAnchorRequired,
      );
    });

    test('three photos, one a verified Face Anchor: eligible', () {
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('trip', 1),
        _photo('dog', 2),
      ];
      expect(
        OnboardingValidators.validatePhotos(
          photos,
          requireFaceAnchor: true,
        ).isSuccess,
        isTrue,
      );
    });

    test('secondary photos need no face at all', () {
      // Nothing about a secondary photo is checked beyond its being there.
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('mountain', 1),
        _photo('motorbike', 2),
        _photo('cat', 3),
        _photo('guitar', 4),
        _photo('beach', 5),
      ];
      expect(
        OnboardingValidators.validatePhotos(
          photos,
          requireFaceAnchor: true,
        ).isSuccess,
        isTrue,
      );
    });

    test('a verified photo that is not the primary one is not enough', () {
      final photos = [
        _photo('dog', 0, primary: true),
        _photo('me', 1, verified: true),
        _photo('car', 2),
      ];
      final result = OnboardingValidators.validatePhotos(
        photos,
        requireFaceAnchor: true,
      );
      expect(
        result.failureOrNull?.message,
        OnboardingMessages.primaryNotFaceAnchor,
      );
    });

    test(
      'a verified flag on a photo moderation has not approved does not count',
      () {
        final photos = [
          _photo('me', 0, verified: true, primary: true, status: 'pending'),
          _photo('trip', 1),
          _photo('dog', 2),
        ];
        final result = OnboardingValidators.validatePhotos(
          photos,
          requireFaceAnchor: true,
        );
        expect(
          result.failureOrNull?.message,
          OnboardingMessages.faceAnchorRequired,
        );
      },
    );

    test('the count limits still apply, and come first', () {
      expect(
        OnboardingValidators.validatePhotos([
          _photo('me', 0, verified: true, primary: true),
          _photo('b', 1),
        ], requireFaceAnchor: true).failureOrNull?.message,
        PhotoUploadMessages.minRequired,
      );
    });

    test('without the requirement the old rule is unchanged', () {
      final photos = [
        _photo('dog', 0, primary: true),
        _photo('trip', 1),
        _photo('car', 2),
      ];
      expect(OnboardingValidators.validatePhotos(photos).isSuccess, isTrue);
    });
  });

  group('primary photo', () {
    final photos = [
      _photo('me', 0, verified: true, primary: true),
      _photo('dog', 1),
      _photo('me2', 2, verified: true),
      _photo('car', 3),
    ];

    test('an ordinary photo cannot become primary', () {
      expect(
        PhotoPolicy.setPrimaryBlockReason(photos, 'dog'),
        PhotoPolicy.primaryRequiresFaceAnchor,
      );
      final unchanged = PhotoPolicy.setPrimary(photos, 'dog');
      expect(unchanged.firstWhere((p) => p.isPrimary).id, 'me');
    });

    test('a verified Face Anchor can become primary, and moves first', () {
      expect(PhotoPolicy.setPrimaryBlockReason(photos, 'me2'), isNull);
      final updated = PhotoPolicy.setPrimary(photos, 'me2');
      expect(_ids(updated), ['me2', 'me', 'dog', 'car']);
      expect(updated.where((p) => p.isPrimary).map((p) => p.id), ['me2']);
      expect([for (final p in updated) p.order], [0, 1, 2, 3]);
    });

    test('an unknown photo cannot become primary', () {
      expect(
        PhotoPolicy.setPrimaryBlockReason(photos, 'nope'),
        PhotoPolicy.notFound,
      );
    });

    test('a member with no verified photo cannot change primary either', () {
      final legacy = [
        _photo('a', 0, primary: true),
        _photo('b', 1),
        _photo('c', 2),
      ];
      expect(
        PhotoPolicy.setPrimaryBlockReason(legacy, 'b'),
        PhotoPolicy.primaryRequiresFaceAnchor,
      );
      // Their existing primary stays exactly as it was.
      expect(
        PhotoPolicy.setPrimary(legacy, 'b').firstWhere((p) => p.isPrimary).id,
        'a',
      );
    });
  });

  group('deleting photos', () {
    test('the only Face Anchor cannot be deleted', () {
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('dog', 1),
        _photo('trip', 2),
        _photo('car', 3),
      ];
      expect(
        PhotoPolicy.deleteBlockReason(photos, 'me'),
        PhotoPolicy.lastFaceAnchor,
      );
      expect(PhotoPolicy.canDelete(photos, 'me'), isFalse);
    });

    test('with two Face Anchors either may be deleted', () {
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('me2', 1, verified: true),
        _photo('dog', 2),
        _photo('car', 3),
      ];
      expect(PhotoPolicy.deleteBlockReason(photos, 'me'), isNull);
      expect(PhotoPolicy.deleteBlockReason(photos, 'me2'), isNull);
    });

    test('deleting the primary anchor promotes the other one', () {
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('dog', 1),
        _photo('me2', 2, verified: true),
        _photo('car', 3),
      ];
      final remaining = PhotoPolicy.normalize(
        photos.where((p) => p.id != 'me').toList(),
      );
      expect(_ids(remaining), ['me2', 'dog', 'car']);
      expect(remaining.first.isPrimary, isTrue);
      expect(remaining.where((p) => p.isPrimary), hasLength(1));
    });

    test('ordinary photos are deleted freely above the minimum', () {
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('dog', 1),
        _photo('trip', 2),
        _photo('car', 3),
      ];
      expect(PhotoPolicy.deleteBlockReason(photos, 'dog'), isNull);
      expect(PhotoPolicy.canDelete(photos, 'car'), isTrue);
    });

    test('the minimum still applies to everything', () {
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('me2', 1, verified: true),
        _photo('dog', 2),
      ];
      expect(
        PhotoPolicy.deleteBlockReason(photos, 'dog'),
        PhotoPolicy.minRequired,
      );
      expect(
        PhotoPolicy.deleteBlockReason(photos, 'me2'),
        PhotoPolicy.minRequired,
      );
    });

    test('a member with no verified photo keeps the old primary rule', () {
      final legacy = [
        _photo('a', 0, primary: true),
        _photo('b', 1),
        _photo('c', 2),
        _photo('d', 3),
      ];
      expect(
        PhotoPolicy.deleteBlockReason(legacy, 'a'),
        PhotoPolicy.primaryDeleteBlocked,
      );
      expect(PhotoPolicy.deleteBlockReason(legacy, 'b'), isNull);
    });
  });

  group('reordering', () {
    final photos = [
      _photo('me', 0, verified: true, primary: true),
      _photo('dog', 1),
      _photo('me2', 2, verified: true),
      _photo('car', 3),
    ];

    test('secondary photos reorder freely', () {
      expect(PhotoPolicy.reorderBlockReason(photos, 1, 3), isNull);
      expect(_ids(PhotoPolicy.reorder(photos, 1, 3)), [
        'me',
        'me2',
        'car',
        'dog',
      ]);
    });

    test('an ordinary photo cannot be dragged into first place', () {
      expect(
        PhotoPolicy.reorderBlockReason(photos, 1, 0),
        PhotoPolicy.primaryRequiresFaceAnchor,
      );
      expect(_ids(PhotoPolicy.reorder(photos, 1, 0)), [
        'me',
        'dog',
        'me2',
        'car',
      ]);
    });

    test(
      'the primary cannot be dragged away leaving an ordinary photo first',
      () {
        expect(
          PhotoPolicy.reorderBlockReason(photos, 0, 3),
          PhotoPolicy.primaryRequiresFaceAnchor,
        );
      },
    );

    test('dragging another anchor first makes it the primary', () {
      final moved = PhotoPolicy.reorder(photos, 2, 0);
      expect(_ids(moved), ['me2', 'me', 'dog', 'car']);
      expect(moved.where((p) => p.isPrimary).map((p) => p.id), ['me2']);
    });

    test('a member with no verified photo reorders as before', () {
      final legacy = [
        _photo('a', 0, primary: true),
        _photo('b', 1),
        _photo('c', 2),
      ];
      expect(PhotoPolicy.reorderBlockReason(legacy, 2, 0), isNull);
      final moved = PhotoPolicy.reorder(legacy, 2, 0);
      expect(_ids(moved), ['c', 'a', 'b']);
      expect(moved.firstWhere((p) => p.isPrimary).id, 'a');
    });
  });

  group('normalize', () {
    test('puts the anchor first when an ordinary photo was marked primary', () {
      final photos = [
        _photo('dog', 0, primary: true),
        _photo('me', 1, verified: true),
        _photo('car', 2),
      ];
      final normalized = PhotoPolicy.normalize(photos);
      expect(_ids(normalized), ['me', 'dog', 'car']);
      expect(normalized.where((p) => p.isPrimary).map((p) => p.id), ['me']);
    });

    test('leaves exactly one primary', () {
      final photos = [
        _photo('me', 0, verified: true, primary: true),
        _photo('me2', 1, verified: true, primary: true),
        _photo('dog', 2, primary: true),
      ];
      expect(
        PhotoPolicy.normalize(photos).where((p) => p.isPrimary),
        hasLength(1),
      );
    });

    test('is stable when applied twice', () {
      final photos = [
        _photo('dog', 3, primary: true),
        _photo('me', 7, verified: true),
        _photo('car', 5),
      ];
      final once = PhotoPolicy.normalize(photos);
      final twice = PhotoPolicy.normalize(once);
      expect(_ids(twice), _ids(once));
      expect(
        [for (final p in twice) p.isPrimary],
        [for (final p in once) p.isPrimary],
      );
    });
  });

  group('photos stored before Face Anchor existed', () {
    final stored = [
      {
        'id': 'a',
        'storagePath': 'users/u/profile/photos/a.jpg',
        'downloadUrl': 'https://cdn.test/a.jpg',
        'moderationStatus': 'approved',
        'order': 0,
        'isPrimary': true,
      },
      {'id': 'b', 'storagePath': 'users/u/profile/photos/b.jpg', 'order': 1},
      'legacy-string-entry',
    ];

    test('parse without the field, and are not treated as verified', () {
      final photos = FirebaseProfileDataSource.photosFromStored(stored);
      expect(photos, hasLength(3));
      expect(photos.any((p) => p.isFaceAnchorVerified), isFalse);
      expect(photos.any((p) => p.isFaceAnchor), isFalse);
      expect(PhotoPolicy.hasFaceAnchor(photos), isFalse);
    });

    test('only the exact boolean true reads as verified', () {
      for (final value in [
        'true',
        1,
        'verified',
        null,
        false,
        <String, Object>{},
      ]) {
        final photos = FirebaseProfileDataSource.photosFromStored([
          {
            'id': 'a',
            'moderationStatus': 'approved',
            'faceAnchorVerified': value,
          },
        ]);
        expect(photos.single.isFaceAnchorVerified, isFalse, reason: '$value');
      }
      final photos = FirebaseProfileDataSource.photosFromStored([
        {'id': 'a', 'moderationStatus': 'approved', 'faceAnchorVerified': true},
      ]);
      expect(photos.single.isFaceAnchor, isTrue);
    });

    test('the default ProfilePhoto is not verified', () {
      const photo = ProfilePhoto(id: 'a', storagePath: 'p');
      expect(photo.isFaceAnchorVerified, isFalse);
      expect(photo.copyWith(order: 2).isFaceAnchorVerified, isFalse);
      expect(
        photo
            .copyWith(isFaceAnchorVerified: true)
            .copyWith(order: 2)
            .isFaceAnchorVerified,
        isTrue,
      );
    });

    test('the flag survives a profile save only when it was true', () {
      const profile = UserProfile(
        uid: 'u',
        displayName: 'Ada',
        photos: [
          ProfilePhoto(
            id: 'a',
            storagePath: 'p/a',
            moderationStatus: 'approved',
            isFaceAnchorVerified: true,
          ),
          ProfilePhoto(id: 'b', storagePath: 'p/b', order: 1),
        ],
      );
      final written =
          FirebaseProfileDataSource.publicProfileMap(profile)['photos']
              as List<Object?>;
      expect((written[0]! as Map)['faceAnchorVerified'], isTrue);
      expect((written[1]! as Map).containsKey('faceAnchorVerified'), isFalse);
    });
  });
}
