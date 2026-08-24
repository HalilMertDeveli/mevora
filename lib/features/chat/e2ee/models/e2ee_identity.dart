class E2eeIdentity {
  const E2eeIdentity({
    required this.publicKeyBase64,
    required this.keyVersion,
    required this.algorithm,
  });

  final String publicKeyBase64;
  final int keyVersion;
  final String algorithm;
}

class E2eeEncryptedPayload {
  const E2eeEncryptedPayload({
    required this.ciphertextBase64,
    required this.nonceBase64,
    required this.macBase64,
    required this.encryptionVersion,
    required this.senderKeyVersion,
  });

  final String ciphertextBase64;
  final String nonceBase64;
  final String macBase64;
  final int encryptionVersion;
  final int senderKeyVersion;

  Map<String, dynamic> toFirestore() {
    return {
      'encrypted': true,
      'ciphertext': ciphertextBase64,
      'nonce': nonceBase64,
      'mac': macBase64,
      'encryptionVersion': encryptionVersion,
      'senderKeyVersion': senderKeyVersion,
      'text': '',
    };
  }

  static E2eeEncryptedPayload? fromFirestore(Map<String, dynamic> data) {
    if (data['encrypted'] != true) {
      return null;
    }
    final ciphertext = data['ciphertext'] as String?;
    final nonce = data['nonce'] as String?;
    final mac = data['mac'] as String?;
    if (ciphertext == null || nonce == null || mac == null) {
      return null;
    }
    return E2eeEncryptedPayload(
      ciphertextBase64: ciphertext,
      nonceBase64: nonce,
      macBase64: mac,
      encryptionVersion: (data['encryptionVersion'] as num?)?.toInt() ?? 1,
      senderKeyVersion: (data['senderKeyVersion'] as num?)?.toInt() ?? 1,
    );
  }
}

class E2eeMediaEnvelope {
  const E2eeMediaEnvelope({
    required this.encryptedBytes,
    required this.keyCiphertextBase64,
    required this.keyNonceBase64,
    required this.keyMacBase64,
    required this.encryptionVersion,
    required this.senderKeyVersion,
  });

  final List<int> encryptedBytes;
  final String keyCiphertextBase64;
  final String keyNonceBase64;
  final String keyMacBase64;
  final int encryptionVersion;
  final int senderKeyVersion;
}
