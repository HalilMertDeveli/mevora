# Date of birth: private to the member

`profiles/{uid}` is readable by every signed-in member. It used to hold the
member's exact `birthDate` next to the `age` the app shows, so any member could
read anyone's date of birth straight from Firestore. It no longer does.

## Where things live now

| Field | Document | Who reads it | Who writes it |
|---|---|---|---|
| `birthDate` | `users/{uid}` | the owner only | the owner's app, once, during onboarding |
| `ageRolloverAt` | `users/{uid}` | the owner only | server only |
| `age` | `profiles/{uid}` | every member | server only |

- **Rules** (`firebase/firestore.rules`). On `users/{uid}` a `birthDate` is
  accepted once, as a past timestamp, and can then be neither changed nor
  removed (`accountBirthDateValid`). On `profiles/{uid}` a client can neither
  add nor change `birthDate` or `age` (`birthDateUnchanged`, `ageUnchanged`,
  `birthDataAbsent`). `ageRolloverAt` is in no client allowlist.
- **`completeOnboarding`** reads the date from the account, refuses under-18s,
  and writes `age` to the profile and `ageRolloverAt` to the account. An `age`
  a client put on the profile is ignored. A date an older app build left on the
  profile is moved to the account in the same transaction.
- **`profileAgeRollover`** (scheduled, daily 00:10 UTC) finds the accounts
  whose `ageRolloverAt` has passed, rewrites the profile's `age` and sets the
  next marker. Because the marker is a moment, a missed run is caught up by the
  next one. Cost: one query read, one profile read and at most two writes per
  member per year.
- **Discovery, Picks, Likes You, same-taste** are unchanged: they already read
  the age through `resolveProfileAge`, which uses the profile's `age` once the
  date is gone.
- **Data export** (`exportMyData`) returns the account document, so the
  member's own date of birth is still in their export. **Account deletion**
  deletes `users/{uid}`, and the date with it. The admin console never showed
  a date of birth and still does not.

A profile served to another member — the Firestore document or any callable's
projection — carries `age` and nothing more precise.

## Deploying (owner-run)

Rules and functions go together, before or with the app build that contains
this change:

```bash
# from a main worktree, after this change is on main
firebase deploy --project mevora-d6ed0 --only functions:completeOnboarding,functions:profileAgeRollover,firestore:rules
```

Why together, and why before the app:

| Combination | Result |
|---|---|
| new rules, old `completeOnboarding` | the new app cannot finish onboarding (`underage`: the old function looks for the date on the profile) |
| old rules, new app | the new app cannot save its first onboarding step (old rules refuse `birthDate` on the account) |
| new rules + new function, old app | existing members keep editing their profiles; an old build cannot onboard a **new** member (it still tries to write the date to the profile) |

`profileAgeRollover` is a new scheduled function: it needs Cloud Scheduler, so
it cannot be created while billing is closed on the project. No new index is
needed — both queries use automatic single-field indexes
(`users.ageRolloverAt`, `profiles.birthDate`).

## Backfill — existing profiles

Deploying does not clean existing documents: every profile written before the
change **keeps exposing its date until the backfill has run**. Run it right
after the deploy above, never before (older functions and app builds read the
date from the profile).

```bash
npm --prefix functions run build
node tool/moveProfileBirthDates.cjs --project mevora-d6ed0            # dry run: counts only
node tool/moveProfileBirthDates.cjs --project mevora-d6ed0 --confirm  # writes
node tool/moveProfileBirthDates.cjs --project mevora-d6ed0            # must report examined: 0
```

Per profile, in one transaction: the account gets `birthDate` (an account that
already has one keeps it) and `ageRolloverAt`; the profile loses `birthDate`
and gets the current `age`. `updatedAt` is not touched. Cost: two reads and two
writes per profile, once.

Profiles with no `users/{uid}` document are listed and left untouched, since
there is no private place to put their date. `--strip-orphans` removes the date
from those too (keeping an age) without creating an account.

The tool is safe to stop and re-run. It was exercised against the Firestore
emulator only; the first production run should be the dry run.

## Rolling back

- Rules or functions: redeploy the previous version. Nothing depends on data
  that only the new version writes.
- The backfill does not need undoing and loses nothing: the date is on
  `users/{uid}`. A completed member's profile keeps a valid `age` for the old
  code, which simply stops rolling it over.

## Known limits

- A member cannot correct a mistyped date of birth; it is locked from the first
  save, as it was before this change.
- The age rule reads calendar fields in the server's time zone (UTC), while the
  app stores midnight of the member's local day. East of UTC that is the
  previous UTC day, so the server counts a birthday up to a day early. This
  predates the change and is unchanged by it.
