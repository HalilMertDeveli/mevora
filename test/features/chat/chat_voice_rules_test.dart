import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/storage.rules').readAsStringSync();
  });

  test('chat voice uploads use participant-scoped paths and audio types', () {
    expect(rules.contains('match /users/{userId}/chat/{matchId}/{fileId}'), isTrue);
    expect(rules.contains('isMatchParticipant(matchId)'), isTrue);
    expect(rules.contains("audio/mp4"), isTrue);
    expect(rules.contains('25 * 1024 * 1024'), isTrue);
  });

  test('firestore allows voice message type', () {
    final firestoreRules = File('firebase/firestore.rules').readAsStringSync();
    expect(firestoreRules.contains("'voice'"), isTrue);
    expect(firestoreRules.contains('voiceStoragePath'), isTrue);
  });
}
