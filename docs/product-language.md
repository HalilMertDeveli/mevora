# Mevora — Product Language

The source of truth for how Mevora talks to people. Read this before writing or
changing any user-facing copy: ARB strings, push notifications, empty states,
buttons, store text. When a string and this document disagree, fix the string.

## Product principle

> Mevora kullanıcının daha fazla profile bakmasını değil, daha az ama daha
> anlamlı profile bakmasını amaçlar.
>
> Mevora is designed to help people look at fewer, more meaningful profiles —
> not more profiles.

Every wording decision answers one question:

> Does this push the person to consume more profiles, or does it help them
> understand and find the right person?

Only the second one ships.

## Core promise

| | |
|---|---|
| TR | **Daha fazla insan değil. Sana daha uygun insanlar.** |
| EN | **Not more people. Better matches for you.** |

Use the promise where Mevora introduces itself (splash, sign-in). Do not stack it
with other slogans on the same screen. Supporting lines, used sparingly:

- *Daha fazla profile bakman gerekmiyor. Doğru profillere bakman gerekiyor.*
- *Daha az profil. Daha anlamlı eşleşmeler.*
- *Find fewer people. Find better matches.*

## Voice

Warm, calm, concise, confident, human, a little premium. Helpful without
sounding like a chatbot.

- **Recommend, never promise.** Mevora suggests people who *may* fit. It never
  claims to know, guarantee or diagnose.
- **Explain why.** Whenever Mevora asks for something (answers, Spotify, humor
  reactions, location), say what it improves first; the technical action second.
- **No swipe language.** The product has Like and Pass; the experience is not
  "swiping". Never describe Mevora as a place to go through people.
- **No engagement bait.** No fake urgency, no "people are waiting", no counts
  meant to pull someone back in.
- **Emojis and exclamation marks are rare.** One small emoji in a playful
  context (Humor Lab, music) is fine; none in headlines, buttons or push copy.
- **Low scores are never insults.** Every compatibility tier is phrased as what
  two people *share*, from strong to modest.

### Turkish

- Address the member as **sen** everywhere in the app. Use **siz / -nız** only
  when the sentence is about *both* people ("Mizahınız çok yakın",
  "Aynı şeyi arıyorsunuz").
- Legal texts (Kullanım Koşulları, Gizlilik Politikası, Topluluk Kuralları) keep
  their formal register on purpose.
- Write Turkish first-hand, not translated English. Prefer
  *"Verdiğin cevapları sana daha uygun insanları seçebilmek için kullanıyoruz."*
  over *"Tarafınızca sağlanan bilgiler … değerlendirilmektedir."*
- Questions that need confirmation use the passive question form:
  *"Bu kişi engellensin mi?"*, not *"Bu kişiyi engelle?"*.

### English

Normal consumer-product English, written for English speakers — not a literal
rendering of the Turkish. *"Let's learn what makes you laugh."*, not
*"Let us learn what you laugh at."*

## Terminology

| Concept | TR | EN | Notes |
|---|---|---|---|
| Main recommendations tab (the Discover deck) | **Senin İçin** | **For You** | Internal code still calls it `discovery`; only the words changed. |
| Daily curated set (`getMevoraPicks`, in development) | **Mevora Picks** · *Bugünün Mevora Picks'i* | **Mevora Picks** · *Today's Mevora Picks* | Reserved for the daily, limited set. Count always comes from data — never hard-code "6". |
| The people Mevora shows | seçimler, *senin için seçtiklerimiz* | picks, *picked for you* | Not "profiles to browse", not "users". |
| Like / Pass actions | **Beğen** / **Geç** | **Like** / **Pass** | Clear controls stay. The *experience* is never called swiping. |
| Super Like action | Öncelikli tanışma | Priority intro | |
| Mutual like | eşleşme · *Birbirinizi seçtiniz* | match · *You chose each other* | |
| Compatibility | **uyum** + a human-readable tier | **match** + a human-readable tier | The percentage is secondary detail. |
| "Why this person?" | *Neden sana uygun olabilir?* · *Neden {isim}?* | *Why they could be right for you* · *Why {name}?* | Only real, data-backed reasons. |
| Relationship questions | **Mevora seni daha iyi tanısın** | **Help Mevora get to know you** | Never "test", "quiz", "exam". |
| Humor Lab | Mizah Labı · **Neye güldüğünü öğrenelim** | Humor Lab · **Let's learn what makes you laugh** | Playful, never "profiling". |
| Spotify | **Müzik zevkin de eşleşmenin bir parçası olsun** | **Let your music taste be part of your match** | Benefit first, then *Spotify'ı bağla / Connect Spotify*. Music never decides a match alone. |
| Profile completion | *Seni daha iyi tanımamıza yardımcı ol* | *Help us get to know you* | Tie the ask to better picks; the % is a detail. |
| Boost | *Profilin, seninle uyumu yüksek kişilere daha önce gösterilir* | *Shown earlier to people you're well matched with* | Describe what Boost really does (see below). |

## Compatibility language

Scores come from the compatibility engine; copy only *describes* them.

### Overall tier

Shown first, with the percentage underneath (`%87 uyum` / `87% match`).
Implemented in `lib/features/compatibility/presentation/compatibility_l10n.dart`
(`CompatibilityL10n.tier`).

| Score | TR | EN |
|---|---|---|
| 80–100 | Güçlü eşleşme | Strong match |
| 65–79 | Birçok konuda yakınsınız | Close on a lot of things |
| 50–64 | Dikkate değer ortak noktalarınız var | Real things in common |
| 0–49 | Bazı ortak noktalarınız var | A few things in common |

### Strongest dimension

When one dimension stands out, say what it means instead of naming a category:

| Dimension | TR | EN |
|---|---|---|
| Relationship intent | Aynı şeyi arıyorsunuz | You want the same thing |
| Values & future | Hayata bakışınız benzer | You see life in similar ways |
| Relationship questions | Birçok soruya benzer cevap verdiniz | You answered a lot of questions alike |
| Music | Müzik zevkinizde güçlü ortak noktalar var | Your music tastes have a lot in common |
| Humor | Mizahınız çok yakın · Benzer şeylere gülüyorsunuz | Your humor is very close · You laugh at similar things |
| Lifestyle | Yaşam tarzlarınız birbirine yakın | Your lifestyles fit together |
| Interests / hobbies | Benzer şeylerden keyif alıyorsunuz | You enjoy similar things |
| Communication | Benzer şekilde iletişim kuruyorsunuz | You communicate in similar ways |

Category bars keep their percentage — they are the detail view.

### Truthfulness rules

1. A sentence exists only when the data behind it exists. *"4 ortak sanatçınız
   var"* means four shared artists in the payload.
2. *"Aynı şeyi arıyorsunuz"* needs both relationship goals present and equal,
   and neither may be *prefer not to say*.
3. Unknown or unmapped reason codes are hidden, never shown raw (no English
   server strings in a Turkish UI, no `short_term` ids).
4. When there is little data, show fewer reasons. Never pad the list.

## Boost and Premium

Boost is measured against the compatibility floor: a boosted profile only gains
ground with people it already clears the floor for, and its eligible radius
widens a little. So the honest description is *"shown earlier, and a little
further out, to people you're well matched with"* — never *"be seen by more
people"* as the whole point.

Premium unlocks insight (who liked you, full music and answer detail). It is
never sold as unlimited profiles or unlimited likes.

## Empty and waiting states

A short list is the product working, not failing.

- *Şimdilik seçimler bu kadar.* / *That's everyone for now.*
- Say what happens next only if the backend does it. Do not promise a time
  ("yarın", "tomorrow") unless a daily refresh really exists for that surface.

## Notifications

Describe the real event, calmly. No exclamation marks, no counts designed to
pull people back, no "someone is waiting".

- Match: *Biriyle birbirinizi seçtiniz. Artık konuşabilirsiniz.* /
  *You and someone chose each other. You can start talking now.*
- Like: *Birisi seni beğendi* / *Someone liked you* — true, and nothing more.
- A "new picks" push is only allowed once a daily picks refresh really exists
  and fired: *Senin için yeni seçimlerimiz var.* / *We have new picks for you.*

Push copy lives in `functions/src/notifications.ts`.

## Avoid

- endless swiping, *kaydırmaya devam et*, *keep swiping*
- *hot profiles*, *🔥 12 NEW MATCHES*, *people are waiting for you*
- *more people*, *more profiles*, *unlimited*
- *compatibility test*, *personality test*, *relationship exam*
- *the algorithm knows*, *AI score*, *your soulmate*, *guaranteed*
- raw ids or server strings in the UI

## Where copy lives

- App strings: `lib/l10n/app_en.arb` (template) and `lib/l10n/app_tr.arb`. See
  `LOCALIZATION_ARCHITECTURE.md` for the pipeline.
- Compatibility phrasing: `lib/features/compatibility/presentation/compatibility_l10n.dart`.
- Push copy: `functions/src/notifications.ts`.
