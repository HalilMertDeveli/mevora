# PHONE AUTH ROOT CAUSE REPORT

**Date:** 2026-08-23  
**Project:** `mevora-d6ed0`  
**Android package:** `com.mevora.app`  
**App ID:** `1:821220262229:android:1a12a39a06a7516f702fdc`

---

## 1. Sorunun gerçek nedeni

Üç katmanlı kırılma (Flutter wiring eksik değildi):

1. **SMS region policy** — Identity Toolkit config’te SMS bölge kısıtı riski vardı. Policy **ALLOW list → yalnızca `TR`** olacak şekilde set edildi. `+90` numaralarına SMS engelleniyorsa bu doğrudan `sms-region-restricted` üretir.
2. **Development’ta `forceRecaptchaFlow: true` varsayılanı** — Sideload/debug build’de Play Integrity yerine reCAPTCHA zorlanıyordu. Activity host yokken / reCAPTCHA akışı bozulunca Firebase **`FirebaseAuthMissingActivityForRecaptchaException` / app-verification** ile SMS’i hiç başlatmıyordu (A/B tipi kırılma).
3. **Hata kodlarının gizlenmesi** — `AuthErrorMapper` Firebase `code` alanını `AuthException`’a yazmıyordu; UI sadece genel “SMS gönderilemedi / beklenmeyen hata” gösteriyordu. Kök neden teşhisi yapılamıyordu.

Doğrulanan sağlam parçalar:

| Kontrol | Sonuç |
| --- | --- |
| Phone provider | **enabled** (Identity Toolkit API) |
| Billing / Blaze | **Yes** |
| Package / project match | `com.mevora.app` ↔ `mevora-d6ed0` |
| Debug SHA-1 / SHA-256 | Keystore ↔ Firebase **eşleşiyor** (yeniden kayıtlandı) |
| `verifyPhoneNumber` callbacks | Mevcut |
| `verificationId` → OTP → credential | Mevcut (empty id artık fail) |
| Test-number bypass (prod) | Kapalı (sadece explicit dart-define) |

---

## 2. Hangi aşamada hata oluşuyordu

**Kritik test sınıflandırması:** çoğunlukla **A) SMS hiç gönderilmiyor**  
(ikincil: app-verification fail → `verificationFailed` before `codeSent`).

Zincir kırılması:

```
Phone input → VERIFY_STARTED → [app verification / region] → VERIFICATION_FAILED
→ codeSent YOK → SMS YOK → OTP ekranı YOK
```

OTP / credential / Firestore / navigation aşamasına çoğu denemede hiç gelinmiyordu.

---

## 3. Firebase hata kodu

Cihaz logu olmadan tek bir sabit kod iddia edilmez. Beklenen kodlar (log’da artık görünür):

- `sms-region-restricted` (bölge)
- `missing-client-identifier` / `app-not-authorized` / `captcha-check-failed`
- `FirebaseAuthMissingActivityForRecaptchaException` (reCAPTCHA + Activity)

Debug UI artık: `Firebase: <code>` satırı ekler.

---

## 4. Yapılan değişiklikler

### Firebase Console / Identity Toolkit
- SMS region policy: **ALLOW → `TR`**
- Android SHA-1 + SHA-256 debug fingerprint’leri doğrulandı / yeniden eklendi
- Phone provider: zaten **enabled** (dokunulmadı)
- Console test number `+905551112233` / `123456` duruyor (yalnızca Console test; app default’ta kullanılmıyor)

### Android
- `MainActivity`: `FlutterActivity` → **`FlutterFragmentActivity`** (reCAPTCHA WebView host)

### Flutter
- `forceRecaptchaFlow` default **false** (Integrity önce; opt-in `FORCE_PHONE_RECAPTCHA=true`)
- `[PHONE_AUTH]` stage logları (telefon/OTP/secret yok)
- Firebase `code` → `AuthException` / `AuthFailure` / debug UI
- Boş `verificationId` → hard fail (`missing-verification-id`)
- Firestore upsert stage log

---

## 5–7. Console / Android / Flutter özeti

Yukarıdaki tablolar.

---

## TEST

Bu ajan oturumunda bağlı cihaz yalnızca **Android emulator** (`emulator-5554`). Kullanıcı şartı: **gerçek telefon + gerçek SMS**. Emulator SMS’i başarı kabul edilmedi; fiziksel cihaz bu ortamda bağlı değildi.

| Check | Result |
| --- | --- |
| Real SMS | **FAIL*** (fiziksel cihaz + kullanıcı OTP’si bu oturumda yok) |
| codeSent | **PENDING** (cihaz testi gerekli; loglar hazır) |
| OTP | **PENDING** |
| Firebase Auth | **PENDING** |
| Firestore | **PENDING** |
| Navigation | **PENDING** |
| Logout | **PENDING** |
| Second Login | **PENDING** |

\* Yapılandırma düzeltmeleri uygulandı; **end-to-end Real SMS henüz bu oturumda kanıtlanmadı.**

Unit tests: `auth_error_mapper` / `phone_auth_controller` çalıştırıldı.

---

## FINAL

**FAIL** — kök nedenler (region + forced reCAPTCHA + gizli error codes + Activity) giderildi; ancak **gerçek telefonda gerçek SMS + OTP doğrulaması bu oturumda tamamlanmadığı** için görev PASS sayılmaz.

### Kullanıcının doğrulama adımları

1. Uygulamayı kaldır, temiz kurulum:
   ```bat
   flutter run --flavor development -t lib/main_development.dart --dart-define=USE_EMULATORS=false
   ```
2. Gerçek `+90…` numara gir → SMS bekle.
3. Flutter console’da sırayı kontrol et:
   `[PHONE_AUTH] START` → `PHONE_NORMALIZED` → `VERIFY_STARTED` → `CODE_SENT` → …
4. SMS gelmezse ekrandaki `Firebase: <code>` satırını paylaş.
5. OTP doğrula → Auth Console’da user → Firestore `users/{uid}` → Discover.
6. Logout + ikinci login.

Tahmin yok: SMS gelmezse log’daki **tam Firebase code** bir sonraki kesin adımı belirler.

---

## 2026-09-29 incident — SMS gelmiyor (yeni kök neden: kapalı fatura hesabı)

Yukarıdaki 2026-08-23 bulguları yalnızca geçmiş olarak kalıyor. Bu olay ayrı ele alındı ve her katman yeniden okundu:

| Kontrol | 2026-09-29 durumu | Kaynak |
| --- | --- | --- |
| Phone provider | enabled | Identity Toolkit `admin/v2 .../config` |
| SMS region policy | allowlist `TR` (değişmedi) | aynı |
| Firebase Android app | `com.mevora.app` ↔ `1:821220262229:android:1a12a39a06a7516f702fdc`, `google-services.json` ve `firebase_options.dart` ile birebir | Firebase Management API |
| Debug SHA-1 / SHA-256 | yerel `debug.keystore` ile Firebase kaydı birebir | `keytool` + Management API |
| Android API key | uygulama kısıtı yok, `identitytoolkit` hedefli | API Keys API |
| App Check (Identity Toolkit) | enforce edilmiyor | App Check API |
| `MainActivity` | `FlutterFragmentActivity` | kaynak |
| **Billing** | proje `billingAccounts/01F531-51FFB0-00D8AC` hesabına bağlı, **hesap `open: false`** | Cloud Billing API |

Kesin kanıt: SMS gönderemeyen, uygulama doğrulama tokenı olmayan bir `+90` isteği `accounts:sendVerificationCode` üzerinden `BILLING_NOT_ENABLED` döndü. Aynı saatlerde Cloud Functions logları da `billing is disabled for this project` yazıyor. Bölge dışı bir numara `OPERATION_NOT_ALLOWED` (region) döndü, yani faturalandırma kontrolü TR numaraları için bölge kontrolünden sonra ve SMS'ten önce çalışıyor.

**Aşama sınıfı: B.** `verifyPhoneNumber` çağrılıyor, Firebase `codeSent` olmadan `verificationFailed(billing-not-enabled)` veriyor. Flutter tarafında SMS'i engelleyen bir kusur yok.

**Çözüm sahibi:** proje sahibi, Google Cloud console'da fatura hesabını yeniden açar ya da projeyi açık bir hesaba bağlar. Bu bir finansal işlem olduğu için hiçbir ajan tarafından yapılmadı.

Bu olayda repo tarafında yapılanlar (`fix/phone-auth-real-sms`):

- `AuthErrorMapper.fromCode`, faturalandırma ve uygulama doğrulama dallarında Firebase kodunu artık düşürmüyor. Debug `Firebase: <code>` satırı her iki yoldan da görünüyor.
- Bölge politikası reddi (`OPERATION_NOT_ALLOWED : SMS unable to be sent until this region enabled…`) artık `sms-region-restricted` olarak raporlanıyor. Önceden "telefon girişi etkin değil" diye yanlış yönlendiriyordu.
- Sahibin gerçek numarası Türkçe `phoneHint` ipucundan, testlerden ve dokümandan kaldırıldı. Yerine sentetik `0532 123 4567` kondu.
