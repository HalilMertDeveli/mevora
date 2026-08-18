import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/features/authentication/data/models/user_document.dart';

void main() {
  test('account paths are keyed by Firebase UID', () {
    expect(FirestorePaths.user('abc'), 'users/abc');
    expect(FirestorePaths.profile('abc'), 'profiles/abc');
    expect(FirestorePaths.location('abc'), 'userLocation/abc');
    expect(FirestorePaths.device('abc', 'pixel'), 'users/abc/devices/pixel');
    expect(
      FirestorePaths.blockedUser('abc', 'xyz'),
      'users/abc/blockedUsers/xyz',
    );
  });

  test('account documents map banned status without dating fields', () {
    final document = UserDocument.fromAccountAndProfile(
      uid: 'user-1',
      account: {
        'email': 'a@mevora.app',
        'phoneNumber': '+905551112233',
        'phoneVerified': true,
        'authProviders': {'phone': true},
        'accountStatus': 'banned',
      },
      profile: {
        'displayName': 'Ada',
        'profileCompleted': true,
        'photos': [
          {'downloadUrl': 'https://example/p.jpg', 'moderationStatus': 'approved'},
        ],
      },
    );

    expect(document.id, 'user-1');
    expect(document.email, 'a@mevora.app');
    expect(document.phoneVerified, isTrue);
    expect(document.accountStatus, AccountStatus.banned);
    expect(document.isBanned, isTrue);
    expect(document.displayName, 'Ada');
    expect(document.profileCompleted, isTrue);
    expect(document.photoUrl, 'https://example/p.jpg');

    final entity = document.toEntity();
    expect(entity.id, 'user-1');
    expect(entity.isBanned, isTrue);
    expect(entity.profileCompleted, isTrue);
  });

  test('storage profile paths stay under the owner uid', () {
    expect(
      StoragePaths.profilePending(ownerUid: 'u1', imageId: 'p1'),
      'users/u1/profile/pending/p1',
    );
    expect(
      StoragePaths.profileApproved(ownerUid: 'u1', imageId: 'p1'),
      'users/u1/profile/p1',
    );
  });
}
