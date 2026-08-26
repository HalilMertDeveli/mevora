# E2EE Protocol Evaluation (Mevora)

## Decision for this program

**Do not migrate to libsignal / Signal Protocol in this delivery wave.**

Mevora continues to use the maintained Dart `cryptography` package with:

- X25519 identity keys
- ECDH + HKDF-SHA256 session derivation (per match)
- AES-256-GCM for text and media

This is **real client-side encryption** of message content (Firebase stores ciphertext), but it is **not** the Signal Protocol and must not be marketed as such.

## Why not libsignal now

| Criterion | Finding |
|-----------|---------|
| Flutter/Dart production SDK | No first-party, widely maintained Signal Protocol binding comparable to native libsignal that Mevora can adopt without custom FFI risk |
| Maintenance / security updates | Custom FFI wrappers go stale; `cryptography` is actively maintained for primitives |
| Scope / regression | Double Ratchet + multi-device would rewrite chat send/receive, media, and key lifecycle — high break risk for working Discover/Chat |
| Honest labeling | Prefer “end-to-end encrypted with X25519/AES-GCM” over implying Signal-grade forward secrecy |

## What we claim

- Firebase Admin/Console cannot read **new** message plaintext when both peers have published identity keys and the client is fail-closed.
- Private identity keys stay on-device (Keystore / Keychain via `flutter_secure_storage`).
- FCM payloads do not include message bodies.

## What we do **not** claim

- Signal Protocol / Double Ratchet
- Forward secrecy after identity compromise
- Multi-device encrypted history sync
- Server-side message content moderation without user-shared evidence
- E2EE for LiveKit calls, profile photos, location, or Q&A

## Future option

If a vetted Flutter-compatible Signal implementation becomes available (license, audits, platform support), evaluate a **versioned** migration (`encryptionVersion` bump) with dual-read of legacy ciphertext and a product decision on multi-device backup.
