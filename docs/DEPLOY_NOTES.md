# Deploying Cloud Functions — read this first

**Never run a bare `firebase deploy --only functions` against `mevora-d6ed0`.**

Twelve functions are live in production whose source is not on `main`. A bare
functions deploy asks Firebase to reconcile production against the current
source, and its answer is to delete anything it cannot find — those twelve
included. Four user-facing features would stop working, and the code to bring
them back is not on `main`.

---

## The twelve

| Deployed function | Source lives on |
|---|---|
| `runMatchingGameRoundNow` | `feature/hourly-global-matching-game` |
| `joinMatchingGameRound` | `feature/hourly-global-matching-game` |
| `submitMatchingGameAnswers` | `feature/hourly-global-matching-game` |
| `getMatchingGameRound` | `feature/hourly-global-matching-game` |
| `getMatchingGameResult` | `feature/hourly-global-matching-game` |
| `matchingGameHourlyTick` | `feature/hourly-global-matching-game` |
| `getMatchingStreak` | `feature/matching-streak` |
| `matchingStreakReminderTick` | `feature/matching-streak` |
| `getWhyYouMatched` | `feature/humor-lab-mvp` |
| `getMatchCompatibilityReveal` | `feature/compatibility-reveal` |
| `createSumsubAccessToken` | `main`, but no longer exported |
| `sumsubWebhook` | `main`, but no longer exported |

The first ten were deployed from feature branches that were never merged.
Deploy is permanent; the merge never happened. The last two are deliberate: the
Didit migration stopped exporting them but left them deployed as a rollback
path until Didit is validated in production.

## How to deploy safely

Deploy only what exists in both places — the intersection of "exported by
`main`" and "already deployed".

```powershell
cd D:\Mevora-deploy
git fetch origin; git checkout --detach origin/main
cd functions; npm ci; npm run build

# Exports the built index actually defines
$env:FIREBASE_CONFIG = '{"projectId":"mevora-d6ed0","storageBucket":"mevora-d6ed0.firebasestorage.app"}'
$env:GCLOUD_PROJECT  = "mevora-d6ed0"
node -e "require('fs').writeFileSync('../.src-exports.txt', Object.keys(require('./lib/index.js')).sort().join('\n'))"

cd ..
$src = Get-Content .src-exports.txt
$dep = & gcloud.cmd functions list --project=mevora-d6ed0 --regions=europe-west1 --format="value(name)"
$only = (($dep | Where-Object { $_ -in $src }) | ForEach-Object { "functions:$_" }) -join ","
npx.cmd firebase deploy --only $only --project mevora-d6ed0 --non-interactive
```

Deploying a single function you just changed is always safe:

```powershell
npx.cmd firebase deploy --only functions:myFunction --project mevora-d6ed0
```

## Two other things that bite

**Deploy from a checkout of `main`, not `D:\Mevora`** if that worktree is on a
feature branch — merged code will simply be absent and you will ship an old
tree. `D:\Mevora-deploy` exists for this.

**`functions/.env.<projectId>` is gitignored**, so a fresh worktree has none and
`firebase deploy --non-interactive` fails asking for `SPOTIFY_CLIENT_ID`,
`GIPHY_API_BASE` and every other `defineString` without a value. Copy the file
across from a worktree that has it.

## Resolving this properly

Three options, none urgent, one of which should eventually be chosen:

1. **Land the features.** Port the four branches onto the current
   architecture and merge. Real work: they carry an older `functions/src/automation`
   module (`adminApi`, `audit`, `notificationRetry`, `premiumSync`) that `main`
   replaced, which is where their merge conflicts come from.
2. **Retire the features.** If they are unused, delete the functions and
   archive the branches.
3. **Leave it, documented.** This file.

Until then the risk is not the state itself — it is someone running the obvious
command and not knowing what it removes.

## Retired: Hourly Mevora ("Saatlik Mevora") and the timed relationship test

Relationship Learning (`functions/src/relationshipLearning/`) replaced both
question-driven matching concepts. Nothing in the app calls them any more, and
nothing on a schedule drives questions or recommendations.

| Deployed function | Status |
|---|---|
| `runMatchingGameRoundNow`, `joinMatchingGameRound`, `submitMatchingGameAnswers`, `getMatchingGameRound`, `getMatchingGameResult` | Hourly Mevora. Never on `main`; retired as a product concept. |
| `matchingGameHourlyTick` | Hourly Mevora's **scheduled** job. Still firing in production until deleted. |
| `dismissRelationshipTestOffer`, `completeRelationshipTest`, `getRelationshipMatches` | The timed 3-question test on Discover. Removed from `main` by `feat/adaptive-relationship-learning`. |

Removing them is a production change, so the owner runs it, after this branch
has landed on `main` and the new functions are deployed:

```powershell
npx.cmd firebase functions:delete runMatchingGameRoundNow joinMatchingGameRound submitMatchingGameAnswers getMatchingGameRound getMatchingGameResult matchingGameHourlyTick dismissRelationshipTestOffer completeRelationshipTest getRelationshipMatches --region europe-west1 --project mevora-d6ed0
```

Data they left behind is not deleted by this: matches created by the old test
keep `source: "relationship_test"` and still render as matches, and the
`relationshipMatch/summary` cooldown fields (`offerCooldownUntil`,
`matchingEventCount`, `matchingPaused`) are simply no longer read. Any hourly
round documents in production stay until someone decides to archive them.
Rollback: redeploy the functions from `feature/hourly-global-matching-game` or
from `main` before this branch.

## Humor Core sequence: what to deploy, and two functions to delete

`feat/humor-core-sequence` replaces the personalised humor calibration and the
global daily set of ten with one canonical sequence (see `docs/HUMOR_LAB.md`).
Nothing is deployed by that branch; this is what the owner runs once it is on
`main`.

Deploy together — the callables keep their names, and the server and the app
should ship in the same release:

```powershell
npx.cmd firebase deploy --project mevora-d6ed0 --only functions:getHumorFeed,functions:submitHumorFeedback,functions:getHumorProfile,functions:getDailyHumorSet,functions:submitDailyHumorResponse,functions:reportHumorContent,functions:getHumorCalibrationPoolReport,functions:adminListHumorCoreSequence
```

No rules or index change: `users/{uid}/humor/core` is covered by the existing
`match /humor/{docId}` rule and by the account-deletion sweep.

| Deployed function | Status |
|---|---|
| `publishDailyHumorSet`, `repairDailyHumorSlot` | Admin callables of the global daily set. Removed from the source: there is no global set any more. |

Delete them after the deploy above:

```powershell
npx.cmd firebase functions:delete publishDailyHumorSet repairDailyHumorSlot --region europe-west1 --project mevora-d6ed0
```

Data left behind is not touched: `humorDailySets/*` manifests are simply no
longer read, and members' old `humorDaily/*` days stay as history. A member's
`humor/core` document is created the first time they open humor after the
deploy. Rollback: redeploy the same eight functions from `main` before this
branch — the old code ignores `humor/core`, and the lifetime profile was never
rewritten.

Do not deploy while the sequence is a draft unless that is intended:
`docs/PUBLISH_BLOCKERS.md`, item 2.
