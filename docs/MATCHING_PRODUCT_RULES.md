# Mevora — matching product rules

The rules every matching feature has to keep: relationship questions, the
compatibility score, daily Picks, Premium and Boost are one system, not four
features. Code that touches any of them is checked against this file.

> **Mevora is not a people warehouse and not an endless swipe app.** It collects
> meaningful answers over time, asks everyone the same questions so people are
> comparable, judges how confident a compatibility score is by how much the two
> people share, and each day shows only a limited number of people who really
> fit — with the reasons.

Money never buys match quality. Premium gives more of the same quality. Boost
gets a member found sooner by people they already fit. What decides who fits
whom is the members' own answers and signals.

Status on 2026-10-01 is in the last column of each table: **live** means the
rule holds on `main`; a branch name means the rule is decided and that branch
implements it.

## 1. Relationship Core

| # | Rule | Status |
|---|---|---|
| C1 | Every member answers the same Core questions in the same order. The order is the list in [Core sequence](#core-sequence); it does not depend on the join date, the device, or anything about the member. | `feat/relationship-core-sequence` |
| C2 | Onboarding asks Q1–Q15. It cannot be skipped and Picks stay closed until it is done. | `feat/relationship-core-sequence` |
| C3 | From the next logical day on, a member gets the next 5 Core questions they have not answered (Q16–20, Q21–25, …). Never more than 5 Core questions a day. A skipped day does not advance. | `feat/relationship-core-sequence` |
| C4 | A logical day is midnight to midnight at UTC+3 on the server clock — the same day as Picks. | live |
| C5 | Each question has a permanent id (`relationship_<slug>_v<n>`) and each option a permanent id. If the meaning or the options change in a way that matters, the id is **not** edited: a new version gets a new id, and the old one is retired (`active: false`) but stays in the sequence. A wording or typo fix keeps the id. | live as convention · enforced by a lock test in `feat/relationship-core-sequence` |
| C6 | New Core questions are appended to the end of the sequence. An existing position never changes. | `feat/relationship-core-sequence` |
| C7 | Nothing in Core asks about religion, politics, health or sexuality, and nothing diagnoses personality or mental state. | live |

Because the order is fixed and nobody can run ahead, the questions two members
share are always the full prefix of the one who has answered fewer. Two members
who finished onboarding share at least 15.

Six of the 64 questions are **importance** questions ("how much does a shared
goal matter to you?"). They are not compared between two people; they set how
much weight that area gets for the member. None of them is in Q1–Q15.

## 2. Deep Dive

| # | Rule | Status |
|---|---|---|
| D1 | A member who wants to answer more than the day's Core does so from a separate, equally standardised pool, in groups of 5, in a fixed order. | `feat/relationship-deep-dive` |
| D2 | Deep Dive never uses up tomorrow's Core questions. | `feat/relationship-deep-dive` |
| D3 | Deep Dive answers feed compatibility the same way: only ids both people answered count. | `feat/relationship-deep-dive` |
| D4 | The pool starts as the 111 `rq_001`–`rq_111` questions. Answers members already gave to them stay valid. | `feat/relationship-deep-dive` |
| D5 | When a member has answered every Core question, the daily 5 come from Deep Dive until new Core questions are appended. | `feat/relationship-deep-dive` |
| D6 | Deep Dive answers are private by default, like Core answers. | `feat/relationship-deep-dive` |

## 3. Compatibility and confidence

| # | Rule | Status |
|---|---|---|
| S1 | A question counts for a pair only when both answered the **same id** (same version). | live |
| S2 | Every other signal — relationship goal, lifestyle, interests, Humor Lab, music — counts only when it is measured on **both** sides. A missing value is not replaced with a neutral guess. | `feat/compatibility-confidence` |
| S3 | A signal that says nothing about the pair (for example how recently someone was active) is not part of the pair score. | `feat/compatibility-confidence` |
| S4 | Confidence is a separate output next to the score. It grows with the number of shared answers and with each further signal measured on both sides. | `feat/compatibility-confidence` |
| S5 | Disagreement is evidence. A pair that shares answers and disagrees gets a low score, not "no data". | `fix/pair-score-correctness` |
| S6 | Nothing can force a score: no key, flag, purchase or Boost sets or raises it. | `fix/pair-score-correctness` (removes the legacy `compatibilityKey` override) |
| S7 | Members' answers are never written to logs. | `fix/pair-score-correctness` |

Proposed starting values — **not approved numbers**. They are fixed only after
the calibration report in `feat/compatibility-engine-measured`:

```
weights     questions .32 · goal .12 · lifestyle .10 · interests .14 · humor .16 · music .16
overall     = Σ measured (weight × score) / Σ measured weight
nEff        = shared Core + 0.5 × shared Deep Dive
cQ          = nEff / (nEff + 8)
confidence  = .32 × cQ + Σ weights of the other measured signals        (0..1)
level       low < .35 ≤ medium < .60 ≤ high
```

## 4. Daily Picks

| # | Rule | Status |
|---|---|---|
| P1 | Each logical day a member gets one set: up to **10** people, or up to **15** with Premium. | 10 live · 15 in `feat/picks-premium-size` |
| P2 | One quality floor for everyone. It is never lower for Premium, for Boost, or for a thin day. | live |
| P3 | The set is never padded. With fewer people above the floor, fewer are shown. | live |
| P4 | A like, a pass or a match never brings a new person the same day. Only a Pick that stopped being eligible (blocked, deleted, hidden, suspended, out of range) may be replaced, within a quarter of the target. | live |
| P5 | A member can like or pass only someone in **today's** set. | #164 on `preview` · today-only and no exceptions in `fix/decision-scope-live-batch` |
| P6 | Every Pick carries the reasons it was chosen, and only reasons backed by data on both sides. | live |
| P7 | The floor is one predicate, used by every path into a set: overall at or above the floor, confidence at or above the minimum, positive evidence on at least one dimension, and at least one category it qualifies for. | live without the confidence term · full in `feat/compatibility-confidence` |
| P8 | There is no other surface for deciding on people. | live (the deck is retired; the music "same taste" list is view-only) |

Someone who liked the member and clears the floor gets priority into the
member's next set, in a small reserved number of places (3 of 10, 4 of 15) and
at the rank their own score earns. It is not a score bonus. Every member gets
this; Premium additionally sees who liked them and why
(`feat/picks-liker-priority`).

## 5. Premium

| # | Rule | Status |
|---|---|---|
| M1 | Premium raises the daily target from 10 to 15. Same floor, same no-padding rule. | `feat/picks-premium-size` |
| M2 | Upgrading during the day grows today's set once by up to 5. Slots already decided are not refilled. A downgrade takes effect the next day. | `feat/picks-premium-size` |
| M3 | Premium unlocks insight: who liked you and why, full music detail. It is never sold as unlimited people or unlimited likes. | live |

## 6. Boost

| # | Rule | Status |
|---|---|---|
| B1 | Boost changes nothing about what the boosting member sees. | live |
| B2 | Boost never changes a compatibility score, stored or shown. | live |
| B3 | A boosted member can appear only in the set of someone for whom they clear the floor (P7) on their own. | live |
| B4 | Boost grants at most **1** place in a set of 10 and **2** in a set of 15, replacements included. A boosted member who earns a place on their own score keeps it and uses that allowance first. | `feat/boost-picks-visibility` |
| B5 | A Boost-granted place goes to the lowest-ranked ordinary Pick's slot, and the boosted member is shown at the rank their own score earns. | `feat/boost-picks-visibility` |
| B6 | Boost does not widen distance. | `feat/boost-picks-visibility` (removes the 25% radius extension) |
| B7 | When several boosted members qualify for the same set, the place rotates by viewer and day. Nobody wins every tie. | `feat/boost-picks-visibility` |
| B8 | Turning Boost off in App Control turns off its effect on Picks too. | `feat/boost-picks-visibility` |

## Core sequence

Proposed order — it freezes when `feat/relationship-core-sequence` lands. The
question text lives in `functions/src/relationshipLearning/catalog.ts`; the
order lives in `functions/src/relationshipLearning/coreSequence.ts`.

| Q | When | Slug | Area | Compared by | Question (TR) |
|---|---|---|---|---|---|
| 1 | Onboarding | `free_evening` | lifestyle | distance | Boş bir akşamı en çok nasıl geçirirsin? |
| 2 | Onboarding | `daily_contact` | communication | distance | Partnerinle gün içinde ne sıklıkla haberleşmek istersin? |
| 3 | Onboarding | `pace` | relationship | distance | Yeni biriyle işler nasıl ilerlesin? |
| 4 | Onboarding | `togetherness_balance` | values | distance | İlişkide ideal denge sence hangisi? |
| 5 | Onboarding | `humor_style` | humor | exact | Hangi mizah sana daha yakın? |
| 6 | Onboarding | `conflict_timing` | communication | matrix | Bir tartışmadan sonra hangisi sana daha yakın? |
| 7 | Onboarding | `marriage_view` | relationship | matrix | Evlilik senin için… |
| 8 | Onboarding | `plans_or_spontaneous` | lifestyle | distance | Planlar konusunda hangisi sana daha yakın? |
| 9 | Onboarding | `jealousy_view` | values | distance | Biraz kıskançlık bir ilişkide… |
| 10 | Onboarding | `feelings_expression` | communication | matrix | Hislerini genelde nasıl ifade edersin? |
| 11 | Onboarding | `children_view` | relationship | matrix | Çocuk sahibi olmak konusunda hangisi sana daha yakın? |
| 12 | Onboarding | `phone_privacy` | values | distance | Partnerlerin birbirinin telefonuna bakması… |
| 13 | Onboarding | `active_lifestyle` | lifestyle | distance | Spor ve hareket hayatında ne kadar yer tutuyor? |
| 14 | Onboarding | `affection_style` | relationship | exact | Sevgini en çok nasıl gösterirsin? |
| 15 | Onboarding | `money_sharing` | values | matrix | Bir ilişkide ortak harcamalar nasıl olmalı? |
| 16 | Day 2 | `exclusivity_timing` | relationship | distance | Birbirinize özel olmayı ne zaman konuşmak istersin? |
| 17 | Day 2 | `late_reply` | communication | distance | Mesajına geç cevap gelmesi seni ne kadar rahatsız eder? |
| 18 | Day 2 | `alone_time` | values | distance | Kendine ayırdığın zamana ne sıklıkla ihtiyaç duyarsın? |
| 19 | Day 2 | `weekend_style` | lifestyle | distance | İdeal hafta sonu… |
| 20 | Day 2 | `goal_importance` | relationship | importance | Aynı ilişki hedefini paylaşmanız ne kadar önemli? |
| 21 | Day 3 | `future_talk` | relationship | distance | Gelecek planlarını konuşmanın doğru zamanı… |
| 22 | Day 3 | `raising_issues` | communication | distance | Seni rahatsız eden bir şeyi ne zaman dile getirirsin? |
| 23 | Day 3 | `honesty_style` | values | distance | Zor bir konuda hangisi sana daha yakın? |
| 24 | Day 3 | `nights_out` | lifestyle | distance | Haftada kaç akşam dışarıda olmayı seversin? |
| 25 | Day 3 | `values_importance` | values | importance | Hayata ve ilişkilere benzer bakmanız ne kadar önemli? |
| 26 | Day 4 | `moving_in` | relationship | distance | Birlikte yaşamak için sana göre doğru zaman… |
| 27 | Day 4 | `friends_one_on_one` | values | distance | Partnerinin yakın arkadaşlarıyla baş başa vakit geçirmesi… |
| 28 | Day 4 | `daily_rhythm` | lifestyle | distance | Günün hangi saatinde daha canlısın? |
| 29 | Day 4 | `tidiness` | lifestyle | distance | Ev düzeni konusunda… |
| 30 | Day 4 | `lifestyle_importance` | lifestyle | importance | Günlük rutinlerinizin uyuşması ne kadar önemli? |
| 31 | Day 5 | `teasing` | humor | distance | Tatlı şakalaşmalar bir ilişkide… |
| 32 | Day 5 | `laugh_together` | humor | exact | Birlikte en çok neye gülmek istersin? |
| 33 | Day 5 | `apart_contact` | communication | exact | Uzaktayken hangisini tercih edersin? |
| 34 | Day 5 | `decision_making` | values | distance | Önemli kararlar bir ilişkide nasıl alınmalı? |
| 35 | Day 5 | `humor_importance` | humor | importance | Birinin seni güldürebilmesi ne kadar önemli? |
| 36 | Day 6 | `together_activity` | interests | exact | Birlikte en çok ne yapmak istersin? |
| 37 | Day 6 | `new_activities` | interests | distance | Birlikte yeni bir şey denemek… |
| 38 | Day 6 | `long_distance` | relationship | distance | Uzak mesafe ilişki senin için… |
| 39 | Day 6 | `money_approach` | values | distance | Paraya yaklaşımın hangisine daha yakın? |
| 40 | Day 6 | `interests_importance` | interests | importance | Ortak ilgi alanlarınızın olması ne kadar önemli? |
| 41 | Day 7 | `music_together` | music | exact | Birlikte müzik dendiğinde aklına ne gelir? |
| 42 | Day 7 | `music_discovery` | music | distance | Yeni müzik keşfetmek… |
| 43 | Day 7 | `public_affection` | relationship | distance | Toplum içinde sevgi göstermek… |
| 44 | Day 7 | `friends_circle` | lifestyle | distance | Partnerinin arkadaşlarınla vakit geçirmesi… |
| 45 | Day 7 | `music_importance` | music | importance | Müzik zevkinizin uyuşması ne kadar önemli? |
| 46 | Day 8 | `household_split` | values | matrix | Ev işleri nasıl paylaşılmalı? |
| 47 | Day 8 | `work_life_balance` | lifestyle | distance | İş ve özel hayat dengesinde… |
| 48 | Day 8 | `joke_when_tense` | communication | distance | Gergin bir anda espri yapılması… |
| 49 | Day 8 | `exes_friendship` | values | distance | Eski sevgililerle arkadaş kalmak… |
| 50 | Day 8 | `holiday_style` | lifestyle | distance | Tatilde seni en çok ne mutlu eder? |
| 51 | Day 9 | `surprises` | relationship | distance | Sürprizler… |
| 52 | Day 9 | `social_media_sharing` | values | distance | İlişkini sosyal medyada paylaşmak… |
| 53 | Day 9 | `pets_at_home` | lifestyle | distance | Evde evcil hayvan… |
| 54 | Day 9 | `hobbies_shared` | interests | distance | Hobilerini partnerinle… |
| 55 | Day 9 | `family_involvement` | values | distance | Ailenin ilişkine dahil olması… |
| 56 | Day 10 | `phones_together` | communication | distance | Birlikteyken telefonlar… |
| 57 | Day 10 | `career_centrality` | values | distance | Kariyer hedeflerin hayatında ne kadar merkezde? |
| 58 | Day 10 | `travel_frequency` | lifestyle | distance | Ne sıklıkla seyahat etmek istersin? |
| 59 | Day 10 | `special_days` | relationship | distance | Özel günleri kutlamak senin için… |
| 60 | Day 10 | `city_or_nature` | lifestyle | distance | Hangisi sana daha iyi gelir? |
| 61 | Day 11 | `hosting` | lifestyle | distance | Evde misafir ağırlamak… |
| 62 | Day 11 | `traditions` | values | distance | Gelenekler ve bayramlar senin için… |
| 63 | Day 11 | `learning_together` | interests | distance | Birlikte yeni bir şey öğrenmek… |
| 64 | Day 11 | `family_visits` | lifestyle | distance | Ailenle ne sıklıkla görüşürsün? |

Onboarding mixes areas on purpose — relationship 4, values 4, communication 3,
lifestyle 3, humor 1 — so a member's first Picks can already cite more than
one kind of reason.

## Changing these rules

A change to a rule here is a product decision by the owner, made before the
code changes. Numbers marked as proposed are fixed in the pull request that
introduces them, with the evidence shown there.
