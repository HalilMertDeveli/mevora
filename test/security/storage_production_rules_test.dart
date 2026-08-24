import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/storage.rules').readAsStringSync();
  });

  test('owners upload pending photos but cannot publish approved photos directly', () {
    expect(rules.contains('match /users/{userId}/profile/pending/{imageId}'), isTrue);
    expect(rules.contains('match /users/{userId}/profile/photos/{imageId}'), isTrue);
    expect(
      rules.contains(
        'allow create, update: if isOwner(userId) && isImage() && isSmallEnough();',
      ),
      isTrue,
    );
    expect(rules.contains('allow create, update, delete: if false;'), isTrue);
  });

  test('storage rejects unknown paths', () {
    expect(rules.contains('match /{allPaths=**}'), isTrue);
    expect(rules.contains('allow read, write: if false'), isTrue);
  });

  test('only safe image formats are allowed for profile pending uploads', () {
    expect(rules.contains('image/jpeg'), isTrue);
    expect(rules.contains('image/png'), isTrue);
    expect(rules.contains('image/webp'), isTrue);
    expect(rules.contains('5 * 1024 * 1024'), isTrue);
  });
}
