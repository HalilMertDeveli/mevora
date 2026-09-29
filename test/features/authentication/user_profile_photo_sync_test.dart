import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/data/datasources/firebase_user_data_source.dart';
import 'package:mevora/features/authentication/data/models/user_document.dart';

Map<String, dynamic> _photo(
  String url, {
  String status = 'approved',
  bool primary = false,
  int? order,
}) => {
  'downloadUrl': url,
  'moderationStatus': status,
  'isPrimary': primary,
  'order': ?order,
};

void main() {
  group('the portrait is the main photo', () {
    String? portrait(List<Object> photos) => UserDocument.fromAccountAndProfile(
      uid: 'u',
      account: const {},
      profile: {'photos': photos},
    ).photoUrl;

    test('the photo marked main wins over list position', () {
      expect(
        portrait([
          _photo('a', order: 1),
          _photo('b', primary: true, order: 0),
          _photo('c', order: 2),
        ]),
        'b',
      );
    });

    test('without a main photo, the first by the member order', () {
      expect(
        portrait([_photo('late', order: 2), _photo('first', order: 0)]),
        'first',
      );
    });

    test('photos still in moderation are skipped', () {
      expect(
        portrait([
          _photo('pending', status: 'pending', primary: true, order: 0),
          _photo('ok', order: 1),
        ]),
        'ok',
      );
    });
  });

  group('the signed-in user follows the profile document', () {
    late StreamController<Map<String, dynamic>?> account;
    late StreamController<Map<String, dynamic>> profile;
    late List<UserDocument?> emitted;
    late StreamSubscription<UserDocument?> sub;

    setUp(() {
      account = StreamController();
      profile = StreamController();
      emitted = [];
      sub = FirebaseUserDataSource.watchAccountAndProfile(
        uid: 'u',
        account: account.stream,
        profile: profile.stream,
      ).listen(emitted.add);
    });

    tearDown(() async {
      await sub.cancel();
      await account.close();
      await profile.close();
    });

    test('photos approved after sign-in reach the user', () async {
      account.add({'email': 'a@mevora.app'});
      profile.add({
        'displayName': 'Ada',
        'photos': [_photo('p', status: 'processing', primary: true)],
      });
      await pumpEventQueue();
      expect(emitted.single?.photoUrl, isNull);

      // Moderation approves the photo: only the profile document changes.
      profile.add({
        'displayName': 'Ada',
        'photos': [_photo('p', primary: true)],
      });
      await pumpEventQueue();
      expect(emitted, hasLength(2));
      expect(emitted.last?.photoUrl, 'p');
    });

    test('a profile write that changes nothing is not re-announced', () async {
      account.add({'email': 'a@mevora.app'});
      profile.add({'displayName': 'Ada'});
      await pumpEventQueue();
      profile.add({'displayName': 'Ada', 'bio': 'hello'});
      await pumpEventQueue();
      expect(emitted, hasLength(1));
    });

    test('a missing account is pending at once, without the profile', () async {
      account.add(null);
      await pumpEventQueue();
      expect(emitted, [null]);
    });

    test('nothing is emitted before the account has been seen', () async {
      profile.add({'displayName': 'Ada'});
      await pumpEventQueue();
      expect(emitted, isEmpty);
    });
  });
}
