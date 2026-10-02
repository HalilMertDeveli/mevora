/// Cryptographic constants for Mevora chat E2EE.
abstract final class E2eeConstants {
  static const String algorithm = 'x25519-aes256gcm-v1';
  static const String hkdfInfo = 'mevora-chat-v1';
  static const String mediaKeyInfo = 'mevora-media-key-v1';
  static const int currentKeyVersion = 1;
  static const String firestoreIdentityDoc = 'identity';
  static const String encryptedContentType = 'application/octet-stream';
  static const String encryptedFileExtension = 'enc';

  /// Body encrypted into the text envelope of an image or voice message.
  ///
  /// A media message carries no caption, but Firestore rules only accept a
  /// message whose `ciphertext` is non-empty (messageEncryptedFieldsValid),
  /// and AES-GCM turns an empty plaintext into an empty ciphertext. Readers
  /// only decrypt the text envelope of text messages, so this value is never
  /// shown.
  static const String mediaEnvelopePlaintext = 'media';
}
