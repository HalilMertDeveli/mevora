import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';

void main() {
  group('StoragePaths.isAllowedChatUpload', () {
    test('allows plaintext AAC voice under 8MB', () {
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: 'audio/mp4',
          sizeBytes: 64 * 1024,
        ),
        isTrue,
      );
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: 'audio/m4a',
          sizeBytes: StoragePaths.maxChatVoiceBytes,
        ),
        isTrue,
      );
    });

    test('rejects oversized plaintext voice', () {
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: 'audio/mp4',
          sizeBytes: StoragePaths.maxChatVoiceBytes + 1,
        ),
        isFalse,
      );
    });

    test('allows E2EE chat blob as application/octet-stream under 25MB', () {
      expect(
        E2eeConstants.encryptedContentType,
        StoragePaths.encryptedChatContentType,
      );
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: E2eeConstants.encryptedContentType,
          sizeBytes: 2 * 1024 * 1024,
        ),
        isTrue,
      );
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: 'APPLICATION/OCTET-STREAM',
          sizeBytes: StoragePaths.maxChatEncryptedBytes,
        ),
        isTrue,
      );
    });

    test('rejects oversized encrypted chat blob', () {
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: StoragePaths.encryptedChatContentType,
          sizeBytes: StoragePaths.maxChatEncryptedBytes + 1,
        ),
        isFalse,
      );
    });

    test('allows chat images under 5MB and rejects empty payloads', () {
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: 'image/jpeg',
          sizeBytes: 100,
        ),
        isTrue,
      );
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: 'audio/mp4',
          sizeBytes: 0,
        ),
        isFalse,
      );
      expect(
        StoragePaths.isAllowedChatUpload(
          contentType: 'text/plain',
          sizeBytes: 10,
        ),
        isFalse,
      );
    });
  });
}
