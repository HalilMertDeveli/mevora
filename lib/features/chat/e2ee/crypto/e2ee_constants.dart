/// Cryptographic constants for Mevora chat E2EE.
abstract final class E2eeConstants {
  static const String algorithm = 'x25519-aes256gcm-v1';
  static const String hkdfInfo = 'mevora-chat-v1';
  static const String mediaKeyInfo = 'mevora-media-key-v1';
  static const int currentKeyVersion = 1;
  static const String firestoreIdentityDoc = 'identity';
  static const String encryptedContentType = 'application/octet-stream';
  static const String encryptedFileExtension = 'enc';
}
