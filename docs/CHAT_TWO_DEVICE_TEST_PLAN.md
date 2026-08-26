# Mevora — İki Cihaz Mesajlaşma Test Planı

Bu doküman **Telefon A (User A)** ve **Telefon B (User B)** arasında gerçek cihaz testi için adım adım rehberdir.

## Önkoşullar

1. Her iki telefona aynı Firebase projesine bağlı build kurulmuş olmalı (`development` veya `production` flavor — ikisi de aynı olmalı).
2. User A ve User B **farklı Firebase Authentication hesapları** olmalı (farklı telefon numarası/e-posta).
3. Her iki kullanıcıda profil tamamlanmış ve Discover açık olmalı.
4. Her iki cihazda **bildirim izni** verilmeli (chat açılınca SnackBar çıkar; *Bildirimleri Etkinleştir*).
5. E2EE için her iki kullanıcı da en az bir kez uygulamayı açıp giriş yapmış olmalı (public key otomatik yayınlanır).

## Match ID Doğrulama

Mevora'da sohbet anahtarı `chatId` değil, **`matchId`**'dir:

```
matchId = sorted(uidA, uidB).join('_')
```

Örnek: `abc123_def456`

Her iki cihazda Matches listesinde aynı kişi görünmeli ve chat açıldığında URL/route aynı `matchId`'yi kullanmalı.

## Debug Log (sadece debug build)

Android Studio / Xcode logcat'te `CHAT` tag'ini filtreleyin. Plaintext mesaj **loglanmaz**. Örnek alanlar:

- `matchId`, `messageId`, `senderId`, `receiverId`, `type`, `encrypted`, `status`

---

## Test Senaryoları

### 1. Login

| Adım | Telefon A | Telefon B |
|------|-----------|-----------|
| 1 | User A ile giriş | User B ile giriş |
| 2 | UID'yi not al (Ayarlar veya log) | UID'yi not al |

**Beklenen:** Mesajlar karışmaz; her cihaz kendi UID'siyle yazar.

### 2. Match Oluşturma

1. A, B'yi Discover'da beğenir.
2. B, A'yı beğenir (karşılıklı like).
3. Her iki cihazda Matches'te görünür.

**Kontrol:** Aynı `matchId`, aynı conversation.

### 3. Text Mesaj (Realtime)

**A → B:** `Merhaba, bu bir test mesajıdır.`

- B anında görür (refresh yok).

**B → A:** `Merhaba, mesajını aldım.`

- A anında görür.

### 4. Çift Taraflı 10+ Mesaj

A↔B en az 10 mesaj. Kontrol: sıra, sender, duplicate yok, kayıp yok.

### 5. Offline

1. B interneti kapat.
2. A mesaj gönderir.
3. B interneti açar → mesaj gelmeli.
4. B cevap verir → crash olmamalı.

### 6. Background / Kapalı Uygulama

1. B uygulamayı background'a al veya kapat.
2. A mesaj gönderir.
3. B'de push notification gelmeli (izin verilmişse).
4. B uygulamayı açınca mesaj görünmeli, duplicate olmamalı.

### 7. Typing Indicator

A yazmaya başlar → B'de "yazıyor..." görünür.
A durur veya gönderir → indicator kaybolur.

**Not:** Privacy ayarında typing kapalıysa görünmez.

### 8. Online / Last Seen

A uygulama açık → B'de A çevrimiçi.
A background/kapalı → B'de son görülme (privacy izin veriyorsa).

### 9. Read Receipt

A mesaj gönderir → B chat'i açar → A'da okundu durumu güncellenir.

### 10. Sesli Mesaj

A: 5+ sn kayıt gönder → B oynat/durdur/devam.
Sonra B → A aynı test.

### 11. Fotoğraf

A → B fotoğraf gönder (galeri/kamera).
B önizleme ve tam ekran kontrol.

### 12. E2EE Doğrulama

A: `Bu mesaj şifreleme testidir.` gönderir.

Firebase Console → `matches/{matchId}/messages/{messageId}`:

- `encrypted: true` olmalı
- `ciphertext` dolu olmalı
- `text` alanı **plaintext içermemeli**

B mesajı düzgün decrypt edip göstermeli.

**Önemli:** Her iki kullanıcı giriş yaptıktan sonra (E2EE bootstrap) test edin. İlk mesaj peer key yoksa geçici plaintext olabilir.

### 13. Security (Manuel)

- User A, B'nin başka match'lerine erişememeli (Firestore client'tan deneme — permission denied).
- Demo/mock match'ler (`mock-*`) gerçek cihazlar arasında senkronize **olmaz**; sadece karşılıklı like ile oluşan gerçek match kullanın.

### 14. Chat Çıkış / Uygulama Restart

Chat'ten çık → tekrar gir → eski mesajlar durur.
Uygulamayı tamamen kapat → aç → mesajlar durur.

### 15. Hızlı Mesajlaşma (20 mesaj)

A: 1, B: 2, A: 3 … en az 20 mesaj. Sıra ve realtime kontrol.

---

## Firebase Yapısı (Referans)

| Kaynak | Yol |
|--------|-----|
| Match | `matches/{matchId}` |
| Mesajlar | `matches/{matchId}/messages/{messageId}` |
| Typing | `matches/{matchId}/meta/typing` |
| Presence | `users/{uid}/presence/current` |
| E2EE public key | `users/{uid}/crypto/identity` |
| Chat medya | `users/{uid}/chat/{matchId}/...` (Storage) |

## Bilinen Sınırlamalar

- Push notification: OS izni verilmeden çalışmaz.
- E2EE: Opportunistic — her iki tarafın da giriş yapıp key yayınlaması gerekir.
- Rate limit: Cloud Function 20 mesaj/dk/match sınırı uygular.
- Demo overlay match'leri sadece local memory'de; iki cihaz arasında çalışmaz.
