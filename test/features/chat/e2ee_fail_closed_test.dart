import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/chat/presentation/chat_strings.dart';

void main() {
  test('chat send path is fail-closed (no plaintext fallback)', () {
    final source = File(
      'lib/features/chat/data/repositories/chat_repository_impl.dart',
    ).readAsStringSync();
    expect(source.contains('_requireE2eeSession'), isTrue);
    expect(source.contains('ChatStrings.encryptionNotReady'), isTrue);
    expect(source.contains('return _dataSource.sendText('), isFalse);
    expect(
      source.contains('return _dataSource.sendMediaMessage('),
      isFalse,
    );
  });

  test('encryption-not-ready copy exists for UI mapping', () {
    expect(ChatStrings.encryptionNotReady.isNotEmpty, isTrue);
  });

  test('storage rules require encrypted chat blobs only', () {
    final rules = File('firebase/storage.rules').readAsStringSync();
    expect(rules.contains('return isEncryptedChatBlob();'), isTrue);
    expect(rules.contains('allow read: if isOwner(userId);'), isTrue);
  });
}
