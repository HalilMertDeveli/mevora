# Mevora — Mevcut Durum, Güvenlik, Backend ve Play Store Yol Haritası

**Tarih:** 2026-08-26  
**Dal:** `docs/readme-complete` (dokümantasyon) · özellik kodu çoğunlukla `backup/wip-before-device-sync-20260824` / `qa/*` hatlarında  
**Amaç:** Uygulamanın şu anki durumunu, kullanıcı güvenliğini, backend yolunu, Google Play hazırlığını, support sitesi kararını ve admin yönetim modelini tek belgede açıkça anlatmak.

> Bu belge **mühendislik gerçeğini** yazar. KVKK / GDPR / Play “yasal uyumluluk” iddiası değildir; hukuki metinler avukat onayı ister.

---

## 1. Şu an uygulamada neredeyiz?

### 1.1 Ürün özeti

Mevora, Flutter + Firebase tabanlı bir dating uygulamasıdır:

| Alan | Durum |
|------|--------|
| Auth (e-posta, telefon, Google, Apple, Spotify girişi) | Çalışıyor |
| Onboarding + 18+ gate | Çalışıyor (istemci + Cloud Function) |
| Profil, fotoğraf (pending → moderasyon) | Çalışıyor |
| Discover / swipe / like-pass | Çalışıyor (adaylar CF üzerinden) |
| Uyumluluk skoru + ilişki soruları | Çalışıyor |
| Matches, chat (metin/görsel/ses), presence | Çalışıyor |
| Chat E2EE (yeni gönderiler fail-closed) | Çalışıyor (Signal seviyesinde değil — dürüst dokümantasyon var) |
| Block / report / unmatch | Çalışıyor |
| Boost IAP | Çalışıyor (consumable) |
| Abonelik (Premium / Likes You gate) | Kısmen — gate + placeholder; tam mağaza abonelik ürünü tam değil |
| Video arama (LiveKit) | Kod var, varsayılan **kapalı** |
| Sumsub doğrulama | Entegrasyon hazır; prod secret gerekir |
| Admin paneli (web) | **Tamamlanmadı** — rules + WIP dalı |
| Google Play yayını | **Henüz hazır değil** — teknik hazırlık yüksek, mağaza checklist açık |

### 1.2 Mimari gerçeklik (kısa)

```text
Flutter App (lib/)
  presentation → controllers (ChangeNotifier)
       ↓
  repositories (domain interfaces)
       ↓
  Firebase Auth / Firestore / Storage / FCM
       ↓
  Cloud Functions (europe-west1, TypeScript)  ← asıl iş kuralları
```

- UI Firestore’a “iş kuralı yazmaz”: match oluşturma, swipe, boost doğrulama, onboarding tamamlaması, silme, rapor → **Functions**.
- State: Riverpod/Bloc yok; **scope + ChangeNotifier**.
- Test: Flutter `test/` + `test/security/` + Functions testleri + smoke tooling.

### 1.3 Git / kalite gerçeği

- `main` görece sakin; aktif özellikler WIP / QA / backup dallarında.
- Son dönem: light tema, tab freeze düzeltmesi, profil soru-cevap düzenleme, privacy/E2EE sertleştirme, multi-user emulator tooling.
- CI smoke workflow var; tam device E2E hâlâ kısmi.

**Özet cümle:** Ürün özellikleri büyük ölçüde var ve backend-otoriter güvenlik modeli kurulmuş; **Play Store yayını + production admin konsolu + hukuki yayın** hâlâ açık iş.

---

## 2. Kullanıcı güvenliği — kullanıcılar ne durumda?

### 2.1 Kimlik ve hesap

| Kontrol | Durum |
|---------|--------|
| Firebase Auth UID birincil anahtar | Evet |
| Şifre/OTP istemci tarafında saklanmaz | Evet |
| 18+ onboarding + sunucu kontrolü | Evet |
| Hesap silme (`deleteUserAccount`) | Evet |
| Veri indirme / export | Evet (E2EE gövdeler export’ta yok) |

### 2.2 Veri izolasyonu (kritik)

| Veri | Kim görür? |
|------|------------|
| Exact GPS / geohash | **Sadece sahibi** — eşlere mesafe etiketi Functions’tan |
| FCM token / cihaz | Owner only |
| Relationship answers (ham) | Owner only; uyumluluk CF hesaplar |
| Profile question answers | Owner veya **aktif match** + `isVisible` |
| Incoming likes | Premium gate **sunucu tarafı** |
| Satın alma / boost wallet yazımı | **Sadece Functions** |
| Admin bayrakları (`isBanned`, …) | Client yazamaz |

### 2.3 Mesajlaşma

- Yeni metin/medya: **E2EE zorunlu** (fail-closed).
- Firestore’da ciphertext; Storage’da encrypted blob.
- FCM’de mesaj gövdesi yok.
- Limit: Double Ratchet / forward secrecy yok — “Signal değil” diye dokümante.

### 2.4 Moderasyon ve güvenlik araçları

- Fotoğraf: client sadece `pending/` yükler; onay Functions + pipeline.
- Report / block: CF + rules; block etkileşimi keser.
- App Check: prod’da Play Integrity / App Attest hedefi; callables emulator dışı enforce.
- Crashlytics / Analytics: hassas alanlar (mesaj, GPS, OTP) parametre olarak yasak.

### 2.5 Kullanıcıya dürüst özet

Kullanıcılar için mevcut mühendislik durumu:

1. Başka kullanıcıların ham konumunu, token’ını, private cevaplarını okuyamaz (rules + CF).
2. Chat içeriği sunucuda düz metin olarak tutulmaz (E2EE); ama **moderatör mesaj içeriğini okuyamaz** — raporlarda kanıt sınırlı olabilir.
3. Uygulama “açık Firestore” değil; default-deny + owner/match scoping.
4. Yasal gizlilik politikası / mağaza Data Safety formu **ayrı iş** — teknik kontrol ≠ hukuki uyumluluk.

Detay: `FIREBASE_SECURITY.md`, `docs/E2EE_SECURITY.md`, `docs/PRIVACY_STORE_READINESS.md`.

---

## 3. Backend — nasıl bir yol izledik?

### 3.1 Tasarım ilkesi

**“Client trusts nothing for money, matching, moderation, or lifecycle.”**

```text
İstemci                     Sunucu (Cloud Functions + Admin SDK)
─────────                   ───────────────────────────────────
UI + local crypto     →     Validation, rate limit, yazım
Owner-read Firestore  ←     Authoritative docs (matches, likes, boosts)
Upload pending only   →     Photo moderation / approve
Swipe intent          →     recordSwipe → match create
```

### 3.2 Ana backend yüzeyleri

| Tür | Örnek |
|-----|--------|
| Callable HTTPS | `completeOnboarding`, `getDiscoveryCandidates`, `recordSwipe`, `saveRelationshipAnswer`, `verifyBoostPurchase`, `deleteUserAccount`, `syncProfileQuestionAnswers`, … |
| Triggers | Fotoğraf upload, (ileride) schedule/automation |
| Rules | `firebase/firestore.rules`, `firebase/storage.rules` |
| Indexes | `firebase/firestore.indexes.json` |
| Bölge | Functions tipik `europe-west1` |

### 3.3 Neden bu yol?

1. Dating ürününde client-side match/boost yazımı kolayca hile olur.
2. Konum paylaşımı yasal/ürün riski — sunucu mesafe üretir.
3. E2EE + App Check + rules üçlüsü mağaza ve abuse için temel.
4. Admin SDK sadece Functions/hosting ops’ta — mobil uygulamaya admin claim yazılmaz.

### 3.4 Operasyonel backend yolu (ileri)

```text
1. Emulator + multi-user seed (tool/qa_multi_user_*)
2. Staging project + App Check debug
3. Production project + Play Integrity / App Attest
4. Rules + Functions deploy → sonra fail-closed client
5. Smoke harness (tools/smoke) + Crashlytics izleme
```

---

## 4. Google Play Store — izlenmesi gereken yol

### 4.1 Karar: Ne zaman store’a çıkılır?

**Şimdi “tam yayın” değil.** Teknik iskelet güçlü; aşağıdaki kapılar kapanmadan production listing açılmamalı.

### 4.2 Önerilen aşamalı yol

#### Aşama A — Store teknik hazırlık (mühendislik)

1. **Release signing** — Play App Signing; debug keystore ile asla store upload yok.
2. **R8 / shrink** planı + ProGuard keep’ler (Firebase, LiveKit, Sumsub).
3. **Production App Check** (Play Integrity) fiziksel cihazda doğrula.
4. **Prod Firebase** rules + indexes + Functions deploy checklist.
5. **Crashlytics** open issues triage; smoke + device regression.
6. **Abonelik / Boost** ürün ID’leri Play Console ile hizala (placeholder bırakma).
7. Video call flag: store v1’de **kapalı** tut (destek yükü düşük).

#### Aşama B — Mağaza politikası (zorunlu formlar)

1. Privacy Policy **canlı URL** (Hosting’de `privacy.html` var → deploy).
2. Terms / Community guidelines URL.
3. **Data Safety** formu (kişisel bilgi, foto, konum, mesajlar, diagnostics, üçüncü taraflar).
4. Hesap silme yolu: uygulama içi + reviewer notu (zaten var — dokümante et).
5. 18+ hedef kitle / Families Policy dışlama netliği.
6. User-generated content: rapor/block/moderasyon açıklaması.

#### Aşama C — Soft launch

1. Internal testing → Closed testing (TR odaklı küçük cohort).
2. Open testing isteğe bağlı.
3. Production: kademeli rollout (%5 → %20 → %100).

#### Aşama D — Sürekli operasyon

- Crash-free sessions hedefi, report SLA, silme/export SLA.
- Admin/moderation kuyruğu (aşağıda).

Checklist referansı: `docs/PRIVACY_STORE_READINESS.md`, `docs/SUPPORT_LEGAL_QA_REPORT.md`.

---

## 5. Support sitesi kurulmalı mı? (Google Play kararı)

### 5.1 Google Play ne ister?

Play, **mutlaka ayrı bir “support website” domain’i** zorlamaz. İstediği pratikte:

| Gereksinim | Minimum yeterli mi? |
|------------|---------------------|
| Privacy Policy URL | Evet — **zorunlu** |
| Uygulama içi hesap silme | Evet |
| Kullanıcı içeriği için rapor/moderasyon | Evet (in-app) |
| Developer contact (e-posta) | Evet — Play Console |
| Yardım / destek | Güçlü tavsiye; web veya in-app |

### 5.2 Mevora’da ne var?

- In-app: Help & Support, FAQ, ticket, Terms, Privacy, Guidelines.
- Static hosting: `hosting/public/privacy.html`, `terms.html`, `help.html`, `guidelines.html`.
- Ticket’lar Firestore `supportTickets` + rules.

### 5.3 KARAR (bu proje için)

**Ayrı “büyük destek sitesi / CMS” şimdi zorunlu değil.**

**Zorunlu olan:**

1. Firebase Hosting ile **public Privacy (+ Terms)** URL’lerini canlı tutmak  
   örn. `https://mevora-d6ed0.web.app/privacy` (veya özel domain).
2. Play Console’da **destek e-postası**.
3. Uygulama içi Support Center’ı production’da açık tutmak.

**İleride (v1.1+) önerilir ama bloklamaz:**

- Basit bir `help.mevora.app` (mevcut HTML’leri custom domain’e bağlamak).
- Status sayfası / bilinen sorunlar (opsiyonel).

**Kurulmaması önerilen (erken aşama):**

- WordPress/Zendesk seviyesinde ayrı ürün sitesi (maliyet + bakım, store engeli değil).

---

## 6. Admin paneli — ne oldu, nasıl yönetilir?

### 6.1 Gerçek durum

| Parça | Durum |
|-------|--------|
| Firestore `isAdmin()` | Rules’ta var |
| Ops koleksiyonları (`auditLogs`, `automationJobs`, `adminReviewQueue`) | Rules / tasarım |
| Flutter dating app içinde admin UI | **Yok** (doğru karar) |
| Hosting `/admin` + automation Functions | **WIP** — `wip/preserve-dirty-tree-20260825` |
| Production RBAC (SUPER_ADMIN / MODERATOR / …) | Planlandı, prod tamam değil |

Kaynak: `docs/ADMIN_PANEL.md`.

### 6.2 Yönetim modeli (hedef mimari)

```text
Dating clients ──┐
                 ├── Firebase Auth + Claims (admin:true / role)
Support staff ───┤
                 └── Firebase Hosting Admin Console
                              │
                              ├── Read: reports, review queue, user lookup
                              ├── Write: sadece CF callables (ban, photo decision, …)
                              └── ASLA: E2EE ciphertext decrypt
```

### 6.3 Günlük operasyon yolu (v1)

**Admin konsol tamamlanana kadar geçici yönetim:**

1. **Firebase Console** (sınırlı, audit’siz — sadece acil).
2. **Report kuyruğu** → Functions / Firestore docs; manuel inceleme.
3. **Photo `manual_review`** → pipeline dokümanı (`docs/PHOTO_MODERATION.md`).
4. **Ban / disable** → Admin SDK script veya CF (client’tan claim verme).
5. **Support tickets** → in-app ticket listesi + e-posta.

**Kalıcı yol (öncelik sırası):**

1. Preserve dalındaki admin WIP’i staging’e çıkar.
2. Custom claims ile `isAdmin` / role.
3. Moderator UI: reports + photo review + user lookup.
4. Audit log zorunlu her admin aksiyonda.
5. Destek rolü: ticket-only (ban yetkisi yok).

### 6.4 Yönetimde kırmızı çizgiler

- Mobil istemciye admin claim yazma.
- Admin’in E2EE mesaj çözmesi (yapılamaz / yapılmamalı).
- Production’da “dry-run’sız” toplu Storage silme.

---

## 7. Sistemleri nasıl kurduk? (açık anlatım)

### 7.1 Katmanlar

1. **Flutter feature modules** — `lib/features/{auth,discovery,chat,matching,profile,…}`  
   data → domain → presentation.
2. **DI scopes** — `lib/core/di/*_scope.dart` InheritedWidget.
3. **Firebase project** — Auth, Firestore, Storage, Functions, FCM, App Check, Crashlytics, Analytics, Hosting.
4. **Security rules** — default deny; owner / match / admin gate.
5. **Cloud Functions** — iş kurallarının tek yazım noktası.
6. **Tests** — unit/widget + `test/security/` contract + Functions + emulator seed.
7. **Docs** — `docs/` + kök `README.md` / `README.tr.md`.

### 7.2 Örnek akışlar

**Discover**

```text
DiscoveryPage → DiscoveryController → getDiscoveryCandidates (CF)
→ skor/boost sıralama → swipe → recordSwipe (CF) → match doc
```

**Chat**

```text
E2EE session → encrypt → Firestore message (ciphertext fields rules)
→ peer decrypt on device → FCM generic ping
```

**Profil soru-cevap**

```text
saveRelationshipAnswer (CF)
  → users/{uid}/relationshipAnswers/{questionId}
  → relationshipMatch/summary
  → users/{uid}/questionAnswers/{questionId} (isVisible)
Edit UI: summary yoksa collection fallback; initState’te scope okuma yok
```

**Güvenlik testi**

```text
test/security/* → rules sözleşmesi (GPS sızmama, client boost yazamama, …)
```

### 7.3 Bilinçli “yapmadıklarımız”

- Client’tan match/boost yazımı.
- Peer’e ham GPS.
- Admin’i dating APK içine gömmek.
- Signal-grade E2EE iddiası.
- Tamamlanmamış admin konsolunu “production ready” ilan etmek.

---

## 8. Öncelikli sonraki 10 iş (özet)

1. Hosting privacy/terms **deploy** + Play URL bağla.  
2. Play Data Safety + avukat metin onayı.  
3. Production App Check (Play Integrity) doğrula.  
4. Release signing + internal testing track.  
5. Admin WIP’i staging’e al (report + photo queue).  
6. Abonelik ürünlerini netleştir veya v1’de kapat.  
7. Video call kapalı tut.  
8. Crashlytics + report SLA.  
9. Dual-device chat/presence regression.  
10. `main` / release branch’e yalnızca doğrulanmış merge.

---

## 9. İlgili dokümanlar

| Konu | Dosya |
|------|--------|
| Mimari | `docs/ARCHITECTURE.md` |
| Güvenlik | `FIREBASE_SECURITY.md` |
| E2EE | `docs/E2EE_SECURITY.md` |
| Privacy / store | `docs/PRIVACY_STORE_READINESS.md` |
| Support / legal QA | `docs/SUPPORT_LEGAL_QA_REPORT.md` |
| Admin | `docs/ADMIN_PANEL.md` |
| Foto moderasyon | `docs/PHOTO_MODERATION.md` |
| Genel README | `README.md` / `README.tr.md` |

---

## 10. Tek cümlelik kararlar

| Soru | Karar |
|------|--------|
| Uygulama ne durumda? | Özellik-zengin, backend-otoriter, store-öncesi. |
| Kullanıcı güvenliği? | Teknik izolasyon güçlü; hukuki yayın + E2EE limitleri bilinçli. |
| Backend yolu? | Functions-authoritative + default-deny rules + App Check. |
| Play Store? | A→B→C aşamalı; soft launch önce. |
| Ayrı support sitesi? | **Şimdi zorunlu değil**; public Privacy URL + in-app support zorunlu. |
| Admin paneli? | Rules hazır, konsol WIP; dating app’te admin yok; claims + Hosting hedef. |
