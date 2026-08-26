# Mevora Chat End-to-End Encryption (E2EE)

This document describes the production E2EE architecture for Mevora direct messages.

## 1. Previous messaging architecture

- Messages stored in `matches/{matchId}/messages/{messageId}` with plaintext `text`.
- Media uploaded to Firebase Storage at `users/{uid}/chat/{matchId}/{messageId}.{ext}` without encryption.
- Cloud Function `sendMessageNotification` updated match previews from message fields.
- FCM payloads already used generic notification types without message body.

## 2. New E2EE architecture

```
User A device                Firebase                 User B device
─────────────                ────────                 ─────────────
plaintext
  ↓ encrypt (AES-GCM)
ciphertext + metadata  →  store ciphertext only  →  download ciphertext
                                                      ↓ decrypt
                                                    plaintext UI
```

Firebase never receives plaintext message bodies or plaintext media.

## 3. Algorithms

| Purpose | Algorithm | Library |
|--------|-----------|---------|
| Identity key pair | X25519 | `cryptography` |
| Session key derivation | ECDH + HKDF-SHA256 | `cryptography` |
| Message encryption | AES-256-GCM | `cryptography` |
| Media encryption | Random AES-256-GCM content key, wrapped with session key | `cryptography` |

Custom crypto primitives are **not** implemented.

## 4. Key exchange

1. Each user generates an X25519 key pair on first chat session.
2. Public key is published to `users/{uid}/crypto/identity`.
3. Private key remains in secure device storage only.
4. Per-match session key = HKDF(X25519(private, peerPublic), info=`mevora-chat-v1`, salt=`matchId`).

## 5. Key storage

| Material | Location |
|----------|----------|
| Private identity key | `flutter_secure_storage` (Android Keystore / iOS Keychain) |
| Public identity key | Firestore `users/{uid}/crypto/identity` |
| Session keys | In-memory cache only (per app session) |

Private keys are never written to Firestore, Storage, logs, or FCM.

## 6. Key rotation (v1)

- `keyVersion` field reserved on identity documents.
- New device without key backup cannot decrypt historical messages (by design).
- If local private key exists but Firestore identity is missing, the client re-publishes the derived public key (no new key pair).

Full multi-device key backup is **not** implemented in v1.

## 7. Text encryption

Firestore fields for encrypted text messages:

- `encrypted: true`
- `ciphertext`, `nonce`, `mac`
- `encryptionVersion`, `senderKeyVersion`
- `text: ""` (always empty)

## 8–11. Media encryption

Images and voice messages:

1. File bytes encrypted client-side with a per-file AES-GCM key.
2. Content key wrapped with the match session key.
3. Encrypted blob uploaded as `application/octet-stream` with `.enc` extension.
4. Envelope metadata stored in the message document (`mediaNonce`, `mediaKeyCiphertext`, …).

## 12. Firestore changes

- Encrypted message schema added alongside legacy plaintext messages.
- New subcollection: `users/{uid}/crypto/identity`.

## 13. Storage changes

- New chat uploads must be encrypted `application/octet-stream` blobs (≤25 MB).
- Legacy plaintext image/audio objects may still exist historically; clients no longer upload them.

## 14–15. Security rules

**Firestore**

- `users/{uid}/crypto/identity`: authenticated read; owner write for public key metadata only.
- New message creates require `encrypted == true` + ciphertext fields; plaintext `text` creates are denied.
- Chat storage paths must be under `users/{auth.uid}/chat/{matchId}/`.

**Storage**

- Pending profile photos: owner read only.
- Chat create: encrypted blob only.

## 16. Cloud Functions

- `sendMessageNotification` uses `🔒` preview for encrypted text instead of `previewText(data.text)`.
- Functions never decrypt message content.

## 17. Notifications

- FCM data payload contains `matchId` only (no plaintext body).
- Notification title/type is generic (`newMessage`, `newPhoto`, `newVoice`).

## 18. Local storage

- No persistent plaintext message database.
- Decrypted content kept in memory for UI rendering.
- Firestore SDK disk cache may contain ciphertext only.
- Private keys: `flutter_secure_storage` with Android Keystore-backed options + iOS Keychain `first_unlock_this_device` (non-synchronizable).

## 19–20. Platform

- Android: private keys in EncryptedSharedPreferences / Keystore via `flutter_secure_storage`.
- iOS: Keychain via `flutter_secure_storage`.

## 21. Test results

Automated tests in `test/features/chat/e2ee_crypto_test.dart` and fail-closed repository tests:

- Text encrypt/decrypt roundtrip
- Wrong key authentication failure
- Media encrypt/decrypt roundtrip
- Public key derivation from private seed
- Send path refuses plaintext when session not ready

## 22. Known limitations

- **Not Signal Protocol** — see `docs/E2EE_PROTOCOL_EVALUATION.md`.
- No forward secrecy (static per-match session key from identity ECDH).
- No server-side search.
- No cross-device private key sync in v1.
- Legacy plaintext messages remain readable for history.
- Fail-closed: if peer has not published a public key, send fails (no plaintext fallback).
- Calls (LiveKit) are not covered by Mevora E2EE.

## 23. Data visible to Firebase

| Data | Visible |
|------|---------|
| Public keys | Yes |
| Ciphertext + crypto metadata | Yes |
| Encrypted media blobs | Yes |
| Plaintext message text | No (new sends) |
| Plaintext media | No (new uploads) |
| Private keys | No |

## 24. Moderation / abuse

Backend cannot read E2EE content. Abuse handling relies on metadata, blocks, rate limits, and **user-shared** evidence when reporting. Child-safety / legal hold product decisions remain open and require policy + legal review.
