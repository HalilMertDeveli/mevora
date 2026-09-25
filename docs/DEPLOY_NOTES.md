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
