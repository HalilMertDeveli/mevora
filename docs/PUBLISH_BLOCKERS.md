# Yayından önce — açık engeller

Uygulamayı mağazaya göndermeden ya da canlı ortama deploy etmeden önce bu listeyi kontrol et. Bir madde kapanınca tarihiyle birlikte buraya yaz.

Adım adım yayın rehberi: `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md`. Anlık durum için:

```bash
node tool/productionReadiness.cjs --online
```

`BLOCKED` satırları bu listedeki maddelerdir; `FAIL` görürsen depo tarafında bir şey bozulmuştur.

## 1. Cloud Billing kapalı — `mevora-d6ed0` ve `mevora-production` (AÇIK)

**Durum (2026-09-29):** `mevora-d6ed0` projesi `billingAccounts/01F531-51FFB0-00D8AC` fatura hesabına bağlı, ama hesap **kapalı** (`"open": false`). Google 2026-09-26'dan beri "billing is disabled for this project" diyor.

**Durum (2026-10-01):** `mevora-production` da kapalı bir fatura hesabına bağlı (`node tool/productionReadiness.cjs --online` ile okundu).

Proje–hesap bağlantısı (`billingInfo`) hâlâ `billingEnabled: true` gösteriyor. Firebase konsolu da normal görünebilir. Bakılması gereken hesabın kendisi.

**Etkisi — billing açılmadan yayınlanırsa:**

| Özellik | Ne olur |
| --- | --- |
| Telefonla giriş (SMS) | SMS hiç gönderilmez. Firebase `BILLING_NOT_ENABLED` döndürür; uygulama "SMS gönderimi için Firebase faturalandırması (Blaze) gerekli." gösterir. Phone Auth SMS'i Spark planında yoktur. |
| Cloud Functions (tüm callable ve zamanlanmış fonksiyonlar) | Çalışmaz: `INTERNAL` / `UNAVAILABLE`. Discover demo profillere düşer; Picks, müzik, seri, ilişki öğrenme, hesap silme ve veri dışa aktarma bozulur. |
| Functions deploy | Yapılamaz. `docs/DEPLOY_NOTES.md` içindeki bekleyen deploy listeleri billing açılana kadar bekler. |
| Secret Manager | Yeni sır oluşturulamaz (`firebase functions:secrets:set`). |

**Yapılacak (yalnızca proje sahibi):** Google Cloud Console → Billing'de `01F531-51FFB0-00D8AC` hesabını yeniden aç ya da projeyi açık bir fatura hesabına bağla. Bu bir finansal işlemdir; hiçbir ajan yapmaz.

**Açıldığını doğrula** (hiçbiri SMS göndermez):

1. `node tool/productionReadiness.cjs --online` → "cloud billing" satırı `PASS` olmalı.
2. `GET https://cloudbilling.googleapis.com/v1/billingAccounts/<hesap>` → `"open": true` olmalı.
3. Uygulama doğrulama tokenı olmayan bir `+90` `accounts:sendVerificationCode` isteği artık `BILLING_NOT_ENABLED` **dönmemeli**. Token eksik olduğu için başka bir hata dönmesi beklenir; yine de SMS gitmez.

Sonra gerçek telefonla bir kez test et (`PHONE_AUTH_IMPLEMENTATION.md`): `[PHONE_AUTH] CODE_SENT` görülmeli ve SMS gelmeli.

Ayrıntı: `docs/PHONE_AUTH_ROOT_CAUSE_REPORT.md` (2026-09-29 bölümü), `PHONE_AUTH_IMPLEMENTATION.md` → "Billing is checked before any SMS".

## 2. Mizah Core sırası taslak — nihai sırayı sen seçeceksin (AÇIK)

**Durum (2026-10-01):** Her üyenin aynı sırayla puanladığı Mizah Core sırası (`functions/src/humor/coreSequence.ts`) şu an **taslak**: `HUMOR_CORE_RELEASE.released = false`. İçinde koddaki 36 kürasyonlu klip, geçici bir sırayla duruyor (ilk 15 = kalibrasyon, sonrası günde 5). 36 klibin 33'ü İngilizce, 3'ü Türkçe etiketli; hepsi GIPHY'den yüklenen üçüncü taraf GIF.

**Dikkat:** `released` bir çalışma zamanı anahtarı **değil**. Bu bayrak `false` iken de taslak sıra üyelere sunulur; onu üyelerden uzak tutan tek şey, Mizah'ın yayın derlemesinde varsayılan olarak kapalı olması (`--dart-define=HUMOR_LAB_ENABLED=true` verilmedikçe).

**Etkisi — sıra yayınlanmadan Mizah açık bir sürüm çıkarsa:** üyeler bu geçici sırayı puanlar. Sıra bir kez üyelere gittikten sonra değiştirmek, önce puanlayanlarla sonra puanlayanları karşılaştırılamaz yapar. Ayrıca 36 içerik, yeni bir üyeye yalnızca 15 + dört günlük set (ve bir içerik) yeter.

**Yapılacak (yalnızca proje sahibi):** V1…Vn için nihai içerikleri ve sırayı seç. Sıra kodda güncellenir, `node tool/lockHumorCoreSequence.cjs --redraft` ile kilit yeniden yazılır, sonra `released: true` yapılır **ve** `functions/test/humorCoreSequence.test.cjs` içindeki `released === false` beklentisi çevrilir; o andan itibaren sıra yalnızca sona ekleme ile büyür.

Ayrıntı: `docs/HUMOR_LAB.md` → "Humor Core sequence"; adımlar `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md` §6.

## 3. Üretim projesi kararı — üretim derlemesi boş bir projeye bağlı (AÇIK)

**Durum (2026-10-01):** `production` flavor'ı `mevora-production` projesine bağlanıyor; bu projede **hiç Cloud Function yok**. Bütün deploy'lar, sırlar, Didit webhook'u, yönetim paneli ve yayındaki politika sayfaları `mevora-d6ed0` üzerinde — o da `development` flavor'ının projesi.

**Etkisi:** bugün alınacak bir üretim derlemesi, arka ucu olmayan bir projeye karşı açılır.

**Yapılacak (yalnızca proje sahibi):** hangi projenin üretim olacağına karar ver. Seçenekler ve sonuçları: `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md` §1.

## 4. Yükleme anahtarı ve Play App Signing parmak izleri (AÇIK)

**Durum (2026-10-01):** yükleme anahtarı (upload key) yok; `android/app/src/production/google-services.json` içinde sertifika parmak izi taşıyan bir Android OAuth istemcisi yok.

**Etkisi:** üretim paketi derlenemez (derleme bilerek durur). Parmak izleri kaydedilmeden Play'den kurulan sürümde Google ile giriş, telefonla giriş ve App Check çalışmaz.

**Yapılacak (yalnızca proje sahibi):** `docs/ANDROID_RELEASE_SIGNING.md`. Anahtarı ajan üretmez.

## 5. Google Play Console: hesap, uygulama, ürünler, RTDN (AÇIK)

**Durum (2026-10-01):** geliştirici hesabı ve uygulama kaydı yok; Boost ürünleri (`mevora_boost_7_days`, `mevora_boost_1_month`, `mevora_boost_1_year`) ve Premium aboneliği Play Console'da tanımlı değil; Play Developer API servis hesabı ve RTDN Pub/Sub konusu kurulmadı.

**Yapılacak (yalnızca proje sahibi):** `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md` adım 3, 5, 11, 13. Kişisel hesapta üretim erişimi için 14 gün boyunca en az 12 kişilik kapalı test şartı var.

## 6. Hukuki onay, veri sorumlusu kimliği ve çocuk güvenliği bildirim süreci (AÇIK)

**Durum (2026-10-01):** politika metinleri (web ve uygulama içi) mühendislik taslağı; hukuki incelemeden geçmedi. Veri sorumlusunun kimliği ve adresi hiçbir sayfada yok; iletişim adresi 2026-10-02'de `destek@mevora.com` olarak değiştirildi (uygulama ve web sayfaları) — bu posta kutusunun açılmış ve okunuyor olması proje sahibinin işi. Topluluk Kuralları ve `/child-safety` sayfası çocuk istismarı içeriğinin yetkililere bildirileceğini söylüyor, ama bunun için işleyen bir süreç yok.

**Etkisi:** Google Play, tanışma uygulamalarından çocuk güvenliği standartları beyanı ve bir iletişim kişisi ister. Süreç yokken beyan vermek yanlış beyan olur.

**Yapılacak (yalnızca proje sahibi / hukuk danışmanı):** `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md` adım 12.

## 7. Mağaza görselleri (AÇIK)

**Durum (2026-10-01):** 512×512 uygulama ikonu, 1024×500 öne çıkan görsel ve mağazaya uygun ekran görüntüleri yok.

**Yapılacak (yalnızca proje sahibi):** `docs/PLAY_STORE_LISTING.md` → "Graphic assets".

## 8. Play'den kurulan sürümle cihaz testi ve Final Production Acceptance (AÇIK)

**Durum (2026-10-01):** App Check (Play Integrity), gerçek SMS, gerçek satın alma, RTDN, canlı Didit ve üretim FCM teslimi hiç denenmedi; bunlar yalnızca Play üzerinden kurulan bir sürümle denenebilir.

**Yapılacak:** `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md` §7 kontrol listesi, ardından ayrı *Final Production Acceptance* çalışması. Geçmeden `preview` → `main` birleştirilmez ve mağazaya gönderilmez.
