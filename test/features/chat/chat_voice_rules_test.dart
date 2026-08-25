import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/storage.rules').readAsStringSync();
  });

  test('chat voice uploads use participant-scoped encrypted blobs', () {
    expect(rules.contains('match /users/{userId}/chat/{matchId}/{fileId}'), isTrue);
    expect(rules.contains('isMatchParticipant(matchId)'), isTrue);
    expect(rules.contains('isEncryptedChatBlob'), isTrue);
    expect(rules.contains('25 * 1024 * 1024'), isTrue);
    // Client still validates original audio types/size before encrypting.
    expect(
      File('lib/core/constants/firestore_paths.dart').readAsStringSync().contains(
        'audio/mp4',
      ),
      isTrue,
    );
    expect(
      File('lib/core/constants/firestore_paths.dart').readAsStringSync().contains(
        'maxChatVoiceBytes',
      ),
      isTrue,
    );
  });

  test('firestore allows voice message type', () {
    final firestoreRules = File('firebase/firestore.rules').readAsStringSync();
    expect(firestoreRules.contains("'voice'"), isTrue);
    expect(firestoreRules.contains('voiceStoragePath'), isTrue);
  });
}
