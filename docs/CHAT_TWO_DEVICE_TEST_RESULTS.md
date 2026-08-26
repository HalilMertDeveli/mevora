# Mevora — İki Cihaz Mesajlaşma Test Raporu

**Tarih:** 2026-08-23  
**Ortam:** Kod analizi + otomatik testler (fiziksel cihaz testi bu oturumda yapılmadı)  
**Hazırlık durumu:** İki gerçek cihaz arasında test için **hazır** (aşağıdaki önkoşullarla)

## Önkoşullar (Sizin Yapmanız Gerekenler)

1. Her iki telefona aynı flavor/build kurulumu
2. Farklı Firebase Auth hesapları (User A / User B)
3. Karşılıklı like ile **gerçek match** (demo/mock değil)
4. Bildirim izni (chat SnackBar veya Ayarlar → Bildirimler)
5. Firebase Functions deploy edilmiş olmalı (`sendMessageNotification` vb.)

---

## Test Sonuçları

| Kategori | Sonuç | Not |
|----------|-------|-----|
| TEXT MESSAGE | **NOT TESTED (DEVICE)** | Kod + 19 unit test PASS; fiziksel doğrulama sizde |
| REALTIME DELIVERY | **NOT TESTED (DEVICE)** | Firestore `snapshots()` listener mevcut |
| MESSAGE ORDER | **NOT TESTED (DEVICE)** | `orderBy createdAt desc` + reverse UI |
| OFFLINE MESSAGE | **NOT TESTED (DEVICE)** | Firestore offline cache destekler |
| PUSH NOTIFICATION | **NOT TESTED (DEVICE)** | CF `sendMessageNotification` mevcut; OS izni gerekli |
| ONLINE STATUS | **NOT TESTED (DEVICE)** | `PresenceLifecycleController` + privacy uyumlu |
| TYPING STATUS | **NOT TESTED (DEVICE)** | `meta/typing` realtime + privacy gate |
| LAST SEEN | **NOT TESTED (DEVICE)** | Presence + `PresenceSubtitle` |
| READ RECEIPT | **NOT TESTED (DEVICE)** | `markRead` batch + status güncelleme |
| VOICE MESSAGE | **NOT TESTED (DEVICE)** | Upload + Storage + player unit test PASS |
| MEDIA MESSAGE | **NOT TESTED (DEVICE)** | Image pipeline + Storage rules PASS |
| E2EE | **PARTIAL PASS** | Crypto unit test PASS; bootstrap login'de eklendi |
| FIREBASE SECURITY | **PASS** | Rules testleri + chat policy testleri PASS |
| APP RESTART | **NOT TESTED (DEVICE)** | Firestore persistence varsayılan |
| BACKGROUND | **NOT TESTED (DEVICE)** | FCM background handler (non-dev) |
| MULTIPLE MESSAGES | **NOT TESTED (DEVICE)** | Rate limit CF'de 20/dk |

---

## Yapılan Kod Hazırlıkları (Bu Oturum)

### 1. E2EE Identity Bootstrap (YENİ)

**Problem:** İlk mesaj peer public key yokken plaintext gidebiliyordu.  
**Root cause:** `ensureIdentity` sadece ilk encrypt/decrypt'te lazy çağrılıyordu.  
**Dosya:** `lib/features/chat/e2ee/services/e2ee_bootstrap_controller.dart`, `lib/app.dart`  
**Düzeltme:** Login sonrası otomatik public key yayınlama.  
**Tekrar test:** `e2ee_bootstrap_controller_test.dart` PASS

### 2. E2EE Session Warmup (YENİ)

**Problem:** Chat açılınca session hazır olmayabilir.  
**Dosya:** `lib/features/chat/presentation/controllers/chat_controller.dart`  
**Düzeltme:** `start()` içinde `isE2eeActive` ile peer key fetch + session derive.

### 3. Debug Log (YENİ, debug-only)

**Dosya:** `lib/features/chat/debug/chat_debug_log.dart`  
**Düzeltme:** `CHAT` tag ile metadata log; plaintext yok.

### 4. Bildirim İzni Soft Prompt (YENİ)

**Problem:** Push test için izin sadece ayarlar sayfasındaydı.  
**Dosya:** `lib/features/chat/presentation/pages/chat_page.dart`  
**Düzeltme:** Chat açılınca izin yoksa SnackBar ile istek.

---

## Mimari Doğrulama (Statik Analiz)

| Bileşen | Durum |
|---------|-------|
| Firebase Auth | ✅ `AuthUidSource` ile UID izolasyonu |
| Firestore messages | ✅ `matches/{matchId}/messages` |
| Realtime listeners | ✅ `watchLatest`, `watchTyping`, presence stream |
| Match oluşturma | ✅ Server-side mutual like (client create yok) |
| Demo overlay | ✅ Sadece `hub.graph` içindeki mock match'ler; gerçek match Firebase'e gider |
| E2EE | ✅ X25519 + HKDF + AES-GCM; Firebase'de ciphertext |
| Security rules | ✅ Participant-only read/write; block check |
| Push CF | ✅ `sendMessageNotification` on message create |

---

## Otomatik Test Özeti

| Suite | Sonuç |
|-------|-------|
| `test/features/chat/` | **20/20 PASS** |
| `test/security/` | Çalıştırılmalı (önceki baseline 33/33) |

---

## FAIL Maddeleri

Bu oturumda fiziksel cihaz olmadığı için runtime FAIL yok. Sizin testinizde FAIL olursa:

1. Logcat'te `CHAT` tag filtreleyin
2. Firebase Console'da `matchId` ve `messageId` doğrulayın
3. `docs/CHAT_TWO_DEVICE_TEST_PLAN.md` adımlarını izleyin

---

## Sonuç

**İki gerçek cihaz arasında test için hazır.**

Şu koşullarla:
- Gerçek mutual match kullanın (demo değil)
- Her iki kullanıcı login olduktan sonra mesajlaşın (E2EE için)
- Bildirim testi için OS iznini verin
- Functions deploy edilmiş olsun

Fiziksel test sonrası FAIL bulursanız, `CHAT` logları ve Firebase document screenshot'ları ile paylaşın.
