# Yayından önce — açık engeller

Uygulamayı mağazaya göndermeden ya da canlı ortama deploy etmeden önce bu listeyi kontrol et. Bir madde kapanınca tarihiyle birlikte buraya yaz.

## 1. Cloud Billing kapalı — `mevora-d6ed0` (AÇIK)

**Durum (2026-09-29):** `mevora-d6ed0` projesi `billingAccounts/01F531-51FFB0-00D8AC` fatura hesabına bağlı, ama hesap **kapalı** (`"open": false`). Google 2026-09-26'dan beri "billing is disabled for this project" diyor.

Proje–hesap bağlantısı (`billingInfo`) hâlâ `billingEnabled: true` gösteriyor. Firebase konsolu da normal görünebilir. Bakılması gereken hesabın kendisi.

**Etkisi — billing açılmadan yayınlanırsa:**

| Özellik | Ne olur |
| --- | --- |
| Telefonla giriş (SMS) | SMS hiç gönderilmez. Firebase `BILLING_NOT_ENABLED` döndürür; uygulama "SMS gönderimi için Firebase faturalandırması (Blaze) gerekli." gösterir. Phone Auth SMS'i Spark planında yoktur. |
| Cloud Functions (tüm callable ve zamanlanmış fonksiyonlar) | Çalışmaz: `INTERNAL` / `UNAVAILABLE`. Discover demo profillere düşer; Picks, müzik, seri, ilişki öğrenme, hesap silme ve veri dışa aktarma bozulur. |
| Functions deploy | Yapılamaz. `docs/DEPLOY_NOTES.md` içindeki bekleyen deploy listeleri billing açılana kadar bekler. |

**Yapılacak (yalnızca proje sahibi):** Google Cloud Console → Billing'de `01F531-51FFB0-00D8AC` hesabını yeniden aç ya da `mevora-d6ed0`'ı açık bir fatura hesabına bağla. Bu bir finansal işlemdir; hiçbir ajan yapmaz.

**Açıldığını doğrula** (ikisi de SMS göndermez):

1. `GET https://cloudbilling.googleapis.com/v1/billingAccounts/<hesap>` → `"open": true` olmalı.
2. Uygulama doğrulama tokenı olmayan bir `+90` `accounts:sendVerificationCode` isteği artık `BILLING_NOT_ENABLED` **dönmemeli**. Token eksik olduğu için başka bir hata dönmesi beklenir; yine de SMS gitmez.

Sonra gerçek telefonla bir kez test et (`PHONE_AUTH_IMPLEMENTATION.md`): `[PHONE_AUTH] CODE_SENT` görülmeli ve SMS gelmeli.

Ayrıntı: `docs/PHONE_AUTH_ROOT_CAUSE_REPORT.md` (2026-09-29 bölümü), `PHONE_AUTH_IMPLEMENTATION.md` → "Billing is checked before any SMS".

## 2. Mizah Core sırası taslak — nihai sırayı sen seçeceksin (AÇIK)

**Durum (2026-10-01):** Her üyenin aynı sırayla puanladığı Mizah Core sırası (`functions/src/humor/coreSequence.ts`) şu an **taslak**: `HUMOR_CORE_RELEASE.released = false`. İçinde koddaki 36 kürasyonlu klip, geçici bir sırayla duruyor (ilk 15 = kalibrasyon, sonrası günde 5).

**Etkisi — sıra yayınlanmadan canlıya çıkarsa:** üyeler bu geçici sırayı puanlar. Sıra bir kez üyelere gittikten sonra değiştirmek, önce puanlayanlarla sonra puanlayanları karşılaştırılamaz yapar. Ayrıca 36 içerik, yeni bir üyeye yalnızca 15 + dört günlük set (ve bir içerik) yeter.

**Yapılacak (yalnızca proje sahibi):** V1…Vn için nihai içerikleri ve sırayı seç. Sıra kodda güncellenir, `node tool/lockHumorCoreSequence.cjs --redraft` ile kilit yeniden yazılır, sonra `released: true` yapılır; o andan itibaren sıra yalnızca sona ekleme ile büyür.

Ayrıntı: `docs/HUMOR_LAB.md` → "Humor Core sequence".
