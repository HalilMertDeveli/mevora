# Google Play store listing package

Draft material for Play Console → *Store presence* and *App content*. Nothing here has
been submitted. Copy follows `docs/product-language.md`: recommend, never promise; no
swipe language; no ranking or performance claims ("best", "#1"), no testimonials, no
prices, no emojis — Google's metadata policy rejects those as well.

Parent document: `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md`.

## Listing text

Limits: title 30 characters, short description 80, full description 4000.

### App name

```
Mevora
```

### Short description — Turkish (default language)

```
Daha fazla insan değil. Sana daha uygun insanlar.
```

### Short description — English

```
Not more people. Better matches for you.
```

### Full description — Turkish

```
Mevora, daha fazla profile bakman için değil, sana daha uygun insanlarla tanışman için tasarlandı.

Çoğu tanışma uygulaması sana bitmeyen bir profil akışı sunar. Mevora tersini yapar: seni tanımaya çalışır ve her gün sınırlı sayıda, sana uygun olabilecek kişiyi önerir.

MEVORA NASIL ÇALIŞIR

• Mevora seni tanır. İlişkiden ne beklediğine, nasıl iletişim kurduğuna ve neye güldüğüne dair kısa sorular yanıtlarsın. Yanıtların yalnızca sana daha uygun kişileri seçmek için kullanılır.

• Mevora Picks. Her gün, yanıtlarına ve tercihlerine göre seçilmiş sınırlı sayıda kişi görürsün. Her öneride neden uygun olabileceğinizi de gösteririz.

• Mizah uyumu. Kısa içeriklere verdiğin tepkilerle neye güldüğünü öğreniriz; mizahı sana yakın kişileri öne çıkarırız.

• Müzik zevkin. İstersen Spotify'ı bağlarsın; ortak sanatçılar ve şarkılar uyumun bir parçası olur. Profilinde neyin görüneceğine sen karar verirsin.

• Karşılıklı beğeniyle eşleşme. Yalnızca birbirini beğenen iki kişi eşleşir ve mesajlaşabilir.

GÜVENLİK VE GİZLİLİK

• Yalnızca 18 yaş ve üzeri.
• Fotoğraf doğrulama: profil fotoğrafının gerçekten sana ait olduğunu kısa bir özçekimle doğrularız.
• Mesajların uçtan uca şifrelenir; içeriklerini biz okuyamayız.
• Tam konumun hiçbir üyeye gösterilmez; yalnızca şehir ve yaklaşık mesafe görünür.
• Her profilde ve sohbette Şikayet et ve Engelle seçenekleri bulunur.
• Hesabını ve verilerini istediğin zaman uygulama içinden silebilir, verilerinin bir kopyasını indirebilirsin.

ÜCRETLİ ÖZELLİKLER

Mevora'yı ücretsiz kullanabilirsin. İsteğe bağlı iki ücretli özellik vardır:
• Boost: profilinin, seninle uyumu yüksek kişilere bir süre daha önce gösterilmesini sağlayan tek seferlik bir satın alımdır.
• Mevora Premium: seni kimlerin beğendiğini görmek gibi ek özellikler sunan, otomatik yenilenen bir aboneliktir. Google Play hesabından dilediğin zaman iptal edebilirsin.

Uyum göstergeleri verdiğin yanıtlara dayanan tahminlerdir; bir eşleşmeyi veya bir ilişkinin sonucunu garanti etmez.

Gizlilik Politikası, Kullanım Koşulları ve Topluluk Kuralları uygulamanın içinde ve web sitemizde yer alır.
```

### Full description — English

```
Mevora is built to help you meet people who suit you better, not to make you look at more profiles.

Most dating apps hand you an endless feed. Mevora does the opposite: it gets to know you and recommends a small number of people each day who could be right for you.

HOW MEVORA WORKS

• Mevora gets to know you. You answer short questions about what you want from a relationship, how you communicate and what makes you laugh. Your answers are used only to choose people who fit you better.

• Mevora Picks. Each day you see a limited set of people chosen from your answers and preferences, with the reasons they could be right for you.

• Humor. Your reactions to short clips tell us what makes you laugh, and we bring forward people whose sense of humor is close to yours.

• Your music taste. Connect Spotify if you like, and shared artists and songs become part of your match. You decide what appears on your profile.

• Matching by mutual like. Only two people who like each other match and can message.

SAFETY AND PRIVACY

• For adults aged 18 and over only.
• Photo verification: a short selfie confirms that your profile photo is really you.
• Your messages are end-to-end encrypted; we cannot read them.
• Your exact location is never shown to other members; they see only your city and an approximate distance.
• Report and Block are available on every profile and in every chat.
• You can delete your account and data from inside the app at any time, and download a copy of your data.

PAID FEATURES

Mevora is free to use. Two optional paid features exist:
• Boost: a one-time purchase that shows your profile earlier, for a period, to people you are highly compatible with.
• Mevora Premium: an auto-renewing subscription with extra features such as seeing who liked you. You can cancel at any time in your Google Play account.

Compatibility indicators are estimates based on the answers you give. They do not guarantee a match or the outcome of a relationship.

The Privacy Policy, Terms of Service and Community Guidelines are available in the app and on our website.
```

### Before pasting — the description must match the build

Remove or adjust any paragraph that the uploaded build does not contain:

| Paragraph | Only true when |
|---|---|
| "Mizah uyumu" / "Humor" | the build was made with `--dart-define=HUMOR_LAB_ENABLED=true` and the Humor Core sequence is released |
| "Mevora Premium" | the build was made with `--dart-define=PREMIUM_ENABLED=true` and the subscription exists in Play Console |
| "Boost" | the Boost products exist and are active in Play Console |
| "Fotoğraf doğrulama" / "Photo verification" | Face Anchor is enforced on the production backend with a live Didit key |

Describing a feature the reviewer cannot find is a metadata-policy rejection.

## URLs

`<site>` is the production Hosting site — `https://mevora-production.web.app`, a custom
domain, or `https://mevora-d6ed0.web.app` if the owner decides that project is
production. The pages exist in `hosting/public/` and must be deployed first.

| Field in Play Console | Value |
|---|---|
| Privacy policy | `<site>/privacy` |
| Delete account URL (Data safety) | `<site>/delete-account` |
| Child safety standards URL | `<site>/child-safety` |
| Terms of Service (for the listing / reviewer notes) | `<site>/terms` |
| Community Guidelines | `<site>/guidelines` |
| Website / support | `<site>/help` |
| Support email | the address the owner chooses — the pages and the app currently use a personal mailbox |

## Category, audience, declarations

Facts for the questionnaires. The owner answers them; do not guess legal classifications.

| Item | Recommended answer | Basis |
|---|---|---|
| App category | Dating | Core function is matchmaking |
| Target age group | **18 and over only** | Server refuses onboarding under 18 (`functions/src/onboarding.ts`) |
| Restrict minor access | **On** — mandatory for dating apps | Play policy; minors then cannot find or install the app |
| Contains ads | No | No ads SDK; `AD_ID` removed |
| Advertising ID | Not used | same |
| App access | **All or some functionality is restricted** — provide reviewer access (below) | Everything is behind sign-in |
| Financial features | None | Declaration is mandatory even when the answer is none |
| Health apps | None | same |
| Government app, news app | No | — |
| Data safety | See `docs/PLAY_DATA_SAFETY_INVENTORY.md` | — |
| Photo and video permissions | No declaration needed | `READ_MEDIA_*` are not requested |
| Location permissions | Foreground only; no background location declaration | Manifest has no background location |
| Foreground services | None declared | — |
| Child Safety Standards | Self-certify **after** the reporting procedure and contact exist (see launch document) | Mandatory for dating apps |

### Content rating (IARC) — facts to answer from

| Topic | Fact |
|---|---|
| Users can interact / communicate | Yes: one-to-one chat (text, voice notes, images) between matched adults |
| Users can share content with others | Yes: profile photos, bio, answers |
| Shares the user's location with other users | Approximate only: city and a distance band; never coordinates |
| Digital purchases | Yes: Boost (one-time) and Premium (subscription) |
| User-generated content moderation | Report and block on profiles and chats; staff review queue; photos checked technically before publishing |
| Sexual content, nudity | Prohibited by the Community Guidelines; not part of the app's own content |
| Violence, drugs, gambling | None in the app's own content |
| Humor content | Third-party GIFs from GIPHY, curated by the owner. **The owner must answer for the humor level of the final sequence** (crude humor, language) |
| Unrestricted internet access | No in-app browser; external links open the system browser |

The dating category normally results in a mature rating. Answer truthfully and accept the
rating that comes out; a misrepresented questionnaire is grounds for removal.

## Reviewer access (App access)

Google's reviewers must be able to sign in and reach every feature. Rules for Mevora:

- **No credentials in the repository or in the app.** They go only into Play Console →
  App content → App access.
- **No bypass in the production app.** The reviewer uses a normal account.

### What the reviewer account needs

| Requirement | How |
|---|---|
| Sign-in that needs no live SMS | An **email + password** account. Email sign-in is implemented, so no test phone number is required. Create it on the production project and verify the address. |
| Onboarding already finished | Complete onboarding by hand on a real device: name, birth date (18+), photos, relationship answers. A reviewer who has to finish a long onboarding may not reach the core features. |
| Photo verification already passed | Face Anchor is enforced for new profiles: the account's primary photo must already be verified, done by a real person. Do not hand reviewers a flow that needs a face match. |
| Something to see | At least one other account that the reviewer account can see in Picks, plus one existing match with a few messages, so chat, report and block can be exercised. |
| Premium, if the build ships it | Add the reviewer's Google account as a **license tester** in Play Console so the purchase is free, or state in the notes that purchase can be tested with the test card. Do not grant Premium by editing data. |

### Notes for the reviewer (template)

Paste into "Any other instructions", with the bracketed parts filled in:

```
Mevora is a dating app for adults (18+).

Sign in: on the first screen choose "E-posta ile devam et" / "Continue with email" and
use the credentials above. No SMS code is needed.

The account has already completed onboarding and photo verification.

Where to find things:
- Recommendations: first tab ("Senin İçin" / "For You").
- Chat: "Eşleşmeler" / "Matches" tab, open the existing conversation.
- Report or block a user: open a profile or a chat, tap the menu (⋯), choose
  "Şikayet et" / "Report" or "Engelle" / "Block".
- Delete account: Settings → Account → "Hesabı sil" / "Delete account".
- Privacy Policy, Terms, Community Guidelines: Settings → Support.
[- Premium: Profile → Mevora Premium. The account is a license tester.]
[- Boost: Profile → Boost.]

App language follows the device language (Turkish or English).
```

Verify every path in the template on the release build before submitting — the labels
above come from the code, not from a device run.

## Graphic assets

Current state (inspected 2026-10-01):

| Asset | Play requirement | State |
|---|---|---|
| App icon | 512 × 512 PNG, 32-bit, ≤ 1024 KB | **Missing.** Only the vector mark exists (`android/app/src/main/res/drawable/ic_mevora_mark.xml`, background `#FAF6F1`). |
| Feature graphic | 1024 × 500 JPEG or 24-bit PNG, no alpha | **Missing.** |
| Phone screenshots | at least 2, each side 320–3840 px, long side ≤ 2× short side | **Missing.** `docs/images/` holds only old sign-in screens with the DEBUG ribbon and the previous design. |
| Tablet screenshots | optional | Not needed for launch. |
| Launcher icon (API 26+) | adaptive icon | Present and correct. |
| Launcher icon (API 24–25) | legacy PNG | `mipmap-*/ic_launcher.png` is still a placeholder "M", not the Mevora mark. Low impact (old devices only) but should be regenerated from the mark. |

Plan for the owner:

1. Export the 512 × 512 icon and regenerate the legacy mipmaps from the vector mark.
2. Design the 1024 × 500 feature graphic. No people who look under 18, no ranking
   claims, no price text.
3. Take 4–8 phone screenshots from the **release** build (no DEBUG ribbon) in Turkish
   and in English: sign-in, Picks, a profile with the "why" reasons, chat, humor (if
   shipped), profile. Use accounts created for the purpose, with photos you have the
   right to publish — never real members.
4. Screenshots must show the actual app. Mock-ups of features the build does not have
   are a policy violation.
