# Humor Lab — Feature Audit

| | |
|---|---|
| **Agent** | Humor Lab Auditor |
| **Task type** | AUDIT (read-only) |
| **Audited at** | `origin/main` @ `dc70a24972ea470d10ff799ff865949696da9140` |
| **Audit date** | 2026-09-22 |
| **Status re-verified at** | `origin/main` @ `803a51a`, 2026-09-25 |
| **Scope** | `functions/src/humor/**`, `lib/features/humor/**`, `lib/core/di/humor_*`, humor blocks in `firebase/firestore.rules` + `firestore.indexes.json`, humor flag wiring, humor tests |

Reviewed: 46 files / ~3,100 LOC. Every finding was traced to a concrete line;
the audit itself changed no production code.

---

## Status since the audit

Humor work landed between the audit and this document reaching `main`, so every
finding below was **re-checked against the code on `2026-09-25`** rather than
left as a snapshot. The `Status` column reflects that re-check, not intent.

| | |
|---|---|
| **Resolved** | 1 of 18 (finding 3) |
| **Partly resolved** | 2 (findings 15, 17) |
| **Still open** | 15 |

Resolved and partly-resolved work landed in
[#40](https://github.com/HalilMertDeveli/mevora/pull/40) (feed pagination),
[#36](https://github.com/HalilMertDeveli/mevora/pull/36) and
[#48](https://github.com/HalilMertDeveli/mevora/pull/48) (calibration core and
content, which brought the first real emulator-backed humor tests).

The two P0 blockers are **both still open**, so the verdict below stands
unchanged: Humor Lab remains effectively dead in production, and the feature
flag is still the only thing keeping that from mattering.

---

## Verdict

The feature is **architecturally sound but not shippable as it stands**.

The domain layer (categories, EMA profile, cosine/overlap scoring, deterministic
safety gate, AI-tagging sanitizer) is clean, pure and well unit-tested. The
problems are all in the **wiring and runtime edges**: the production build never
reaches the backend, the remote kill switch is dead code, and the feed
structurally runs dry.

Two blockers (P0) mean Humor Lab is effectively **dead in production today** —
which is also why none of this has surfaced as a live incident.

---

## Priority summary

| # | Severity | Finding | Location | Status |
|---|---|---|---|---|
| 1 | **P0** | Release builds ship the mock data source | `humor_services_factory.dart:25` | Open |
| 2 | **P0** | Remote Config flag is never applied — no kill switch | `mevora_remote_config.dart:49` | Open |
| 3 | **P1** | Feed permanently dries up; seen cards consume page slots | `feed.ts:88`, `contentRepository.ts:97` | **Fixed** (#40) |
| 4 | **P1** | Giphy sync can never work in production (`secrets: []`) | `humor/index.ts:288` | Open |
| 5 | **P1** | Undo is cosmetic — the rating stays applied server-side | `humor_controller.dart:234` | Open |
| 6 | **P2** | "Save" silently writes a phantom `funny` rating | `humor_controller.dart:250` | Open |
| 7 | **P2** | Peer humor vector leaks via `differences` (UI never uses it) | `compatibility.ts:47` | Open |
| 8 | **P2** | Unvalidated `contentId` → Firestore path injection + queue pollution | `humor/index.ts:137` | Open |
| 9 | **P2** | No rate limiting on any humor callable | `humor/index.ts` (all) | Open |
| 10 | **P2** | `avgRating` computed from a non-transactional read | `feedback.ts:39,131` | Open |
| 11 | **P2** | Media host allowlist bypassable (`host.includes`) | `contentValidation.ts:43` | Open |
| 12 | **P2** | `skip()` sends `neutral`, flattening every profile dimension | `humor_controller.dart:226` | Open |
| 13 | **P3** | Dead branch in `runHumorModeration` active computation | `humor/index.ts:243` | Open |
| 14 | **P3** | `viewCount` is always equal to `ratingCount` | `feedback.ts:143` | Open |
| 15 | **P3** | Unsigned, client-controlled, unbounded feed cursor | `feed.ts:45` | Partly (#40) |
| 16 | **P3** | Rules expose `humorVector` / `safetyFlags` on direct reads | `firestore.rules:717` | Open |
| 17 | **P3** | Test gaps: no callable/rules enforcement coverage | `functions/test`, `test/security` | Partly (#36, #40, #48) |
| 18 | **P3** | `upsertHumorContentDoc` stats read-modify-write outside a tx | `contentRepository.ts:183` | Open |

---

## P0 — Blockers

### 1. Release builds ship the mock data source

```dart
// lib/core/di/humor_services_factory.dart:25
const useMock = bool.fromEnvironment('USE_MOCK_HUMOR', defaultValue: true);
```

`USE_MOCK_HUMOR` appears in exactly four places in the repo: this line, its own
doc comment, and two lines of `docs/HUMOR_LAB.md`. **No build script, Gradle
config, or CI workflow passes `--dart-define=USE_MOCK_HUMOR=false`.**

Every release build therefore constructs `MockHumorDataSource`. The moment
someone enables the feature flag, users get hardcoded placeholder cards
(`picsum.photos`, Google sample MP4s) with no backend call, no profile
persistence, and no moderation path.

*Fix direction:* invert the default (`defaultValue: false`) and let local QA opt
*into* the mock, or resolve it from `AppEnvironment` instead of a dart-define.
A safe default should not be "fake data".

### 2. Remote Config flag is never applied — there is no kill switch

```dart
// lib/core/config/remote_config/mevora_remote_config.dart:49
FeatureFlags toFeatureFlags(FeatureFlags current) { ... }
```

`toFeatureFlags` has **no call site in `lib/`** — only `remote_config_test.dart`
calls it. `RemoteConfigDataSource` has a single implementation,
`DefaultRemoteConfigDataSource`, which returns compile-time constants; nothing
is wired to Firebase Remote Config.

Consequences for Humor Lab:

- `humorLabEnabled` can only be turned on via `--dart-define=HUMOR_LAB_ENABLED`
  or a debug development build (`bootstrap.dart:182`). The documented RC switch
  does nothing.
- There is **no way to remotely disable the feature** after release. For a
  UGC-adjacent surface with user-reported content, losing the kill switch is a
  moderation-response risk, not just a product one.
- This is not Humor-Lab-specific: `videoCallEnabled`, `premiumEnabled`,
  `maintenanceMode` and `boostCatalogJson` are all equally inert. **Flagged for
  a separate audit** — it is out of Humor Lab's scope to fix.

---

## P1 — High

### 3. The feed structurally dries up, and seen cards waste page slots

> **Fixed** in [#40](https://github.com/HalilMertDeveli/mevora/pull/40).
> `listCandidateHumorContent` is gone; the feed now walks the catalog newest
> first from an explicit cursor, drops seen items *before* ranking, and stops
> the cursor on the last item served rather than the last scanned. Verified on
> the Firestore emulator at 400 of 400 items served versus 120 before. The
> description below is kept as the record of what the defect was.

Two independent defects that compound:

**(a) Fixed 120-document candidate window, no ordering.**

```ts
// functions/src/humor/feed.ts:88
const candidates = await listCandidateHumorContent(input.db, {languages, limit: 120});

// functions/src/humor/contentRepository.ts:97-108
const limit = Math.min(200, Math.max(input.limit, 40));      // -> 120
let query = db.collection('humorContent')
  .where('active','==',true).where('safetyStatus','==','approved').limit(limit);
if (languages.length === 1) { query = query.where('language','==',languages[0]); }
```

There is no `orderBy` and no cursor on the Firestore query, so it returns the
same first 120 documents in `__name__` order on every call, forever. The default
language preference is `['tr','en']` — length 2 — so the language filter is
*skipped* and post-filtered in memory, which can shrink 120 candidates down to a
handful of Turkish cards.

Once a user has rated those 120 cards, `getHumorFeed` returns `items: []`
permanently, no matter how large the catalog grows.

**(b) `seen` filtering runs after ranking and slicing.**

```ts
// functions/src/humor/feed.ts:95-105
const ranked = rankHumorFeed({ profile, items: ..., limit })  // returns <= limit
  .filter((c) => !seen.has(c.contentId));                     // then removes seen
const page = ranked.slice(0, limit);
```

`rankHumorFeed` already caps its output at `limit`, and it deliberately includes
seen items (`novelty: 0`). Worse, the exploration pass sorts by
`exploration desc, affinity asc` — which *favours* seen items with a high
exploration bonus. Those get picked into the ~18% exploration slots and are then
thrown away by the filter, so a request for 12 cards routinely returns far fewer.

Also note `loadSeenContentIds` caps at 500 (`feed.ts:36`): past 500 interactions
the user starts seeing repeats, while `submitHumorFeedback` silently re-rates
them without incrementing the count.

*Fix direction:* exclude seen ids **before** ranking, page the Firestore query
with a real cursor (`orderBy createdAt desc` — the composite index at
`firestore.indexes.json:62` already exists for it), and either raise or
server-side-paginate the seen set.

### 4. Giphy sync can never work in production

```ts
// functions/src/humor/index.ts:288-293
export const syncHumorFromProvider = onCall(
  { ...callableOptions, secrets: [] },   // <- secret not bound
```

`humorApiConfig.ts` declares `defineSecret('GIPHY_API_KEY')`, but the callable
binds **no** secrets, so the secret is never mounted into the function's
environment. `resolveGiphyApiKey()` finds nothing in `process.env`, the
`giphyApiKey.value()` call throws, the `catch` swallows it and returns `null`.

The admin therefore always gets `{ok: false, configured: false, "Set
GIPHY_API_KEY..."}` — even after running the exact command the message tells them
to run. The `docs/HUMOR_LAB.md` setup instructions cannot succeed.

*Fix direction:* `secrets: [giphyApiKey]`. The comment "Secret optional at
deploy; runtime checks configuration" reflects a misunderstanding — declaring the
secret is what makes the runtime check meaningful.

### 5. Undo is cosmetic

```dart
// lib/features/humor/presentation/controllers/humor_controller.dart:234-248
Future<void> undo() async {
  ... _state = _state.copyWith(currentIndex: target, canUndo: false, clearLastRated: true);
  notifyListeners();
  _markViewed(_state.items[target]);
}
```

`rate()` has already awaited `submitHumorFeedback`, which persisted the
interaction and applied the EMA update to `users/{uid}/humor/summary`. `undo()`
only rewinds the `PageView` index — it calls no repository method, and no
retract/undo callable exists.

The user sees an undo affordance (`humorUndoRating` tooltip,
`humor_lab_page.dart:129`) and reasonably concludes the rating was withdrawn. It
was not. The test at `humor_controller_test.dart:45` asserts only that the index
moved back, so this passes CI.

Note the backend *does* support correction: re-rating the same `contentId`
applies a fresh EMA without double-counting (`feedback.ts:88-105`). So a real
undo is implementable — it just needs to be called.

*Fix direction:* either wire undo to re-submit the prior rating (or a dedicated
retract callable), or rename the control to "back" and drop the undo semantics.

---

## P2 — Medium

### 6. "Save" writes a phantom rating

```dart
// humor_controller.dart:250-261
final result = await _repository.submitFeedback(
  contentId: item.contentId,
  rating: _state.lastRated ?? HumorRating.funny,   // <- invented
  saved: true,
);
```

Bookmarking a card the user has *not* rated records `funny`, which increments
`interactionCount`, moves the humor vector, and bumps the content's `avgRating`.
Saving is a bookmark gesture, not an opinion; it should not train the profile.

*Fix direction:* make `rating` nullable on the feedback path so `saved: true`
can be persisted without a scoring signal.

### 7. Peer humor vector leaks through `differences`

```ts
// functions/src/humor/compatibility.ts:47-58
function differenceRows(a, b, limit = 3) {
  return HUMOR_CATEGORIES.map((dim) => ({dim, a: a[dim], b: b[dim], gap: ...}))
    ... .map(({dim, a: av, b: bv}) => ({dim, a: av, b: bv}));  // b = peer's raw 0-100 value
}
```

`getMatchHumorCompatibility` returns up to three of the *other user's* raw
normalized humor-vector values per call. `firestore.rules:419` and `:716` both
state "Peers never read raw humor vectors" and block the direct read — the
callable hands them over anyway.

`humor_compatibility_sheet.dart` never renders `differences`, and
`functions_humor_data_source.dart:214` parses it into an unused entity. So this
is a privacy leak that buys nothing.

*Fix direction:* drop `b` from the payload (return a qualitative gap bucket), or
remove `differences` entirely until a UI needs it.

### 8. Unvalidated `contentId` → path injection and queue pollution

```ts
// functions/src/humor/index.ts:137-169
const contentId = String(data.contentId ?? "").trim();
if (!contentId) { throw new HttpsError("invalid-argument", "contentId"); }
...
await db.doc(`humorReports/${uid}_${contentId}`).set(...);
await db.doc(`humorModerationQueue/${contentId}`).set(...);
```

No charset check, no length cap (contrast `submitHumorFeedback`, which at least
caps at 128 chars — `index.ts:70`). A `contentId` containing slashes changes the
document path: `"x/y/z"` yields `humorModerationQueue/x/y/z`, a valid four-segment
path, so the write lands in an attacker-chosen nested subcollection. An odd
segment count instead throws and surfaces as an unhandled `internal` error —
`reportHumorContent` is the only humor callable with no `try/catch`.

Separately, the content is never verified to exist or to be servable, so any
authenticated user can flood `humorModerationQueue` with `needs_review` entries
for arbitrary ids, degrading the moderator queue and Firestore cost.

Blast radius is limited — both collections are admin-read-only
(`firestore.rules:724,730`) so nothing is *exposed* — but this is write
amplification under a user's control.

*Fix direction:* validate against `/^[A-Za-z0-9_-]{1,128}$/` in all four
callables that interpolate `contentId` into a path (`report`, `feedback`,
`upsert`, `runHumorModeration`), and require the content document to exist before
enqueuing a report.

### 9. No rate limiting on humor callables

The repo has `functions/src/messageRateLimit.ts` and a `users/{uid}/rateLimits`
collection locked down at `firestore.rules:431`. No file under
`functions/src/humor/` references either.

`submitHumorFeedback` writes 3 documents per call, `getHumorFeed` reads up to
620 (120 candidates + 500 interaction ids), and `reportHumorContent` writes 2 —
all uncapped per user. That is a cost-amplification and moderation-abuse surface.

### 10. `avgRating` is computed from a stale, non-transactional read

```ts
// functions/src/humor/feedback.ts:39
const content = await loadHumorContent(input.db, input.contentId);   // outside the tx
...
// :131-150 — inside the tx
const prevCount = Number(content.stats?.ratingCount ?? 0);
const nextAvg = prevCount <= 0 ? weight : (prevAvg * prevCount + weight) / nextCount;
tx.set(contentRef, {stats: {ratingCount: FieldValue.increment(1), avgRating: nextAvg}}, {merge: true});
```

`ratingCount` uses an atomic increment, but `avgRating` is a plain overwrite
derived from a snapshot taken before the transaction opened. Two concurrent
raters both read `prevCount = N` and each write an average computed as if they
were the only one — last write wins, and the running average drifts from the
true mean. `avgRating` feeds `qualityScore` (`ranking.ts:29`), so ranking
degrades exactly as content gets popular.

*Fix direction:* read `contentRef` inside the transaction, or store
`ratingSum` as an increment and derive the average on read.

### 11. Media host allowlist is bypassable

```ts
// functions/src/humor/contentValidation.ts:43-58
const allowed = ALLOWED_HOST_HINTS.some(
  (hint) => host === hint || host.endsWith(`.${hint}`) || host.includes(hint));
if (!allowed && item.sourceUrl) {
  const src = new URL(item.sourceUrl);
  if (!src.hostname.includes("giphy.com")) { return {ok: false, reason: "host-not-allowed"}; }
}
```

Two weaknesses:

- `host.includes(hint)` makes the exact-match and suffix-match checks redundant
  and matches `giphy.com.attacker.tld` or `evil-picsum.photos.cdn.tld`.
- The `sourceUrl` escape hatch admits **any** https media host as long as the
  (separately attacker-supplied) `sourceUrl` string contains `giphy.com`.

Today only admin callables and the Giphy adapter feed this function, so this is
defence-in-depth rather than an open hole — but defence-in-depth is precisely
what this function exists for. The stray `"giphy.gif"` entry in the list also
matches nothing real.

*Fix direction:* exact host or true suffix match only (`host === h ||
host.endsWith('.' + h)`), and drop the `sourceUrl` bypass.

### 12. `skip()` flattens the humor profile

```dart
Future<void> skip() => rate(HumorRating.neutral, skipped: true);
```

`neutral` carries weight `0.0` (`profile.ts:22`), so the EMA target becomes
`50 + 50*0 = 50` for *every* dimension (`profile.ts:76-77`) — each skip pulls the
whole vector toward the neutral centre and increments `interactionCount`, which
raises `confidence`.

A user who skips a lot ends up with a high-confidence, perfectly average profile:
the opposite of the intent. Skipping should record the interaction (for `seen`
deduplication) without applying a vector update.

---

## P3 — Low / cleanup

**13. Dead branch** — `humor/index.ts:243-246`:

```ts
const active = safetyStatus === "approved" && snap.data()?.active !== false
  ? safetyStatus === "approved"
  : safetyStatus === "approved";     // both branches identical
```

`active` is then ignored anyway (line 251 recomputes it). The apparent intent —
honouring a pre-existing `active: false` — is lost, so re-moderating a manually
deactivated card silently reactivates it.

**14. `viewCount` is meaningless** — incremented only inside
`if (!alreadyCounted)` (`feedback.ts:143`), so it is always identical to
`ratingCount`. Views are never recorded on their own.

**15. Unsigned, unbounded cursor** — `feed.ts:45-57` base64-decodes
client-supplied JSON into a `Set` with no size cap. A client can send a
multi-megabyte cursor (memory pressure) or forge one to skip content. Signing it
or capping the decoded array would cost a few lines.

**16. Rules expose internals on direct reads** — `firestore.rules:717` allows any
authenticated client to read the *whole* `humorContent` document, including
`humorVector` and `safetyFlags`. `toFeedSafeContent` (`contentRepository.ts:21`)
carefully strips exactly those fields from the callable response. Either limit
the rule or accept the exposure and drop the stripping — the two should agree.

**17. Test gaps.** Unit coverage of the pure domain layer is genuinely good
(11 backend tests, 9 Flutter tests). Missing:

- No callable tests at all — auth/admin gating, `contentId` validation, the
  feedback transaction, and the report flow are untested.
- `test/security/firestore_production_rules_test.dart:156-182` is a
  **string-`contains` test on the rules file**, not an emulator test. It asserts
  that the text `'Peers never read raw humor vectors'` is present — which, per
  finding 7, is currently false in behaviour while passing in CI.
- No test covers feed pagination, the `seen` filter, or an exhausted feed —
  which is why finding 3 is invisible today.

**18. `upsertHumorContentDoc` stats race** — `contentRepository.ts:183-190` reads
`existing.data()?.stats` and writes it back outside any transaction, clobbering
increments that land in between. Low frequency (admin-only path).

---

## What is solid

Worth stating explicitly, since the finding list is long:

- **Domain layer** — `categories.ts`, `profile.ts`, `compatibility.ts`,
  `ranking.ts` are pure, deterministic, dependency-free and properly unit-tested.
  The EMA / confidence / learning-rate model is coherent and well documented.
- **Safety gate** — `classifyHumorSafety` is deterministic and zero-tolerance on
  `minorRelated` / `illegal` / `extreme`; AI proposals are sanitized through
  `applyHumorAiTagging` and explicitly marked `usedForUserScoring: false`.
  Good separation of "AI suggests" from "server decides".
- **Rules posture** — every humor collection is client-write-denied; all writes
  go through Cloud Functions. `humorReports` is reporter-or-admin read.
- **Licensing** — the no-scraping stance is real, not just documented: the
  adapter interface only has a licensed-API and an internal implementation.
- **Clean architecture** — the Flutter side follows the repo's
  entity / repository / datasource / controller layering consistently, with
  `Result`-based error handling throughout.
- **Isolation** — the MVP promise that Humor Lab does not touch
  `calculateCompatibility` or Discover ranking holds; nothing outside
  `lib/features/humor` and `functions/src/humor` reads the humor profile.

---

## Recommended fix branches

Per the repository's one-task-one-branch rule, **do not fix these in
`audit/humor-lab`**. Suggested split:

| Branch | Findings | Class | Notes |
|---|---|---|---|
| `fix/humor-release-wiring` | 1 | CONTROLLED_PARALLEL | Touches `humor_services_factory.dart` only |
| `fix/humor-feed-exhaustion` | 3 | CONTROLLED_PARALLEL | `feed.ts` + `contentRepository.ts`; needs a paging cursor design |
| `fix/humor-giphy-secret` | 4 | SAFE_PARALLEL | One-line `secrets:` binding + a deploy smoke test |
| `fix/humor-undo-semantics` | 5, 6, 12 | CONTROLLED_PARALLEL | All three are `humor_controller.dart` + the feedback contract |
| `fix/humor-callable-hardening` | 8, 9, 11 | CONTROLLED_PARALLEL | `contentId` validation, rate limits, allowlist |
| `fix/humor-privacy-differences` | 7 | SAFE_PARALLEL | Backend payload + unused Flutter entity |
| `fix/humor-stats-consistency` | 10, 13, 14, 18 | SAFE_PARALLEL | Transaction + dead-code cleanup |
| `test/humor-callable-coverage` | 17 | SAFE_PARALLEL | Emulator tests for callables + real rules tests |
| *(separate audit)* | 2 | — | Remote Config is app-wide, not Humor Lab's to fix |

**Suggested merge order:** 4 → 1 → 3 → 8/9/11 → 5/6/12 → 7 → 10/13/14/18 → 17.
Findings 1 and 3 decide whether the feature can be enabled at all; 17 should land
before any of the behavioural fixes are trusted.

**Shared-file risk:** `firestore.rules`, `firestore.indexes.json` and
`functions/src/index.ts` are only touched by the feed-paging and hardening
branches. No humor fix needs `pubspec.yaml`, `app_router.dart` or
`bootstrap.dart` except finding 1 (`humor_services_factory.dart`, humor-owned).
