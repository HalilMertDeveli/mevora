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

## Which day a birthday falls on

The app stores a date of birth as midnight of the picked day on the member's
own clock (`saveBirthDate`): 11 April picked in Istanbul is
`1996-04-10T21:00:00Z`. The server's day is UTC. Read as it stands, that
instant is 10 April for everyone east of UTC, so the server used to count the
birthday — the public `age`, and the 18+ check in `completeOnboarding` — a day
early.

The server now reads the stored instant as a calendar day: **the nearest UTC
midnight** (`birthCalendarDate` in `functions/src/profileSafety.ts`). A local
midnight is at most twelve hours from the UTC midnight of the same day on any
clock from UTC-12 to UTC+12, so that is the day the member picked. The age and
the next `ageRolloverAt` are computed from that day and from today's date in
UTC (`ageFromBirthDate`, `nextAgeChangeAt`), whatever zone the process runs in.

| Member's clock | 11 April is stored as | Read as | Age changes at |
|---|---|---|---|
| Istanbul, UTC+3 | 10 April 21:00 UTC | 11 April | 11 April 00:00 UTC (03:00 in Istanbul) |
| London, UTC+0 / +1 | 11 April 00:00 / 10 April 23:00 UTC | 11 April | 11 April 00:00 UTC |
| Los Angeles, UTC-7 | 11 April 07:00 UTC | 11 April | 11 April 00:00 UTC, as before |
| Auckland in winter, UTC+12 | 10 April 12:00 UTC | 11 April | 11 April 00:00 UTC |
| Auckland in summer, UTC+13 | 10 April 11:00 UTC | **10 April** | 10 April 00:00 UTC — see Known limits |

- **Nothing stored changes.** The app writes what it wrote before and the
  rules are untouched; `users/{uid}.birthDate` is never rewritten. A date
  stored as UTC midnight is read as itself, so an app build that one day
  writes UTC midnight needs no server change and no migration.
- **Every reader uses the one rule**: `completeOnboarding`, the daily
  roll-over, the backfill tool, and `resolveProfileAge` for a profile whose
  date has not been moved to the account yet.
- **Markers written by the earlier rule correct themselves.** Such a marker
  comes due on the day before the birthday. The roll-over then finds the age
  unchanged, leaves the profile alone and writes the right marker; the next
  day's run moves the age. Cost: one extra query read, profile read and
  account write for that member, once. Nothing needs recomputing by hand.

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

The birthday rule (see "Which day a birthday falls on") is function code only
and adds nothing to this command: no rules, index, app or data change. If the
functions above were ever deployed without it, redeploying the same two is the
whole fix — markers they wrote correct themselves. Functions outside the
command (Discovery, Picks, Likes You) derive an age from a date only for a
profile the backfill has not reached; once it has run they read the
server-written `age`.

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
- **Clocks beyond UTC+12** (UTC+12:45 to UTC+14: New Zealand during daylight
  time, Chatham, Tonga, Samoa, Tokelau, Kiribati's Line Islands). Midnight
  there is 10:00–11:15 UTC on the previous day, nearer that day's UTC midnight
  than the picked day's, and the stored instant cannot be told apart from one
  written at UTC-10 to UTC-11:15 (Hawaii, French Polynesia) for the previous
  day. The server reads the day before, so these members' birthday is still
  counted a day early — as it was before, not made worse. Closing it needs the
  app to store a date that carries no clock (UTC midnight of the picked day);
  the server already reads such a value correctly.
- **Exactly UTC-12** reads a day late. Nobody lives on that clock; the tie goes
  to UTC+12, which stores the same instant.
- **The server's day is UTC.** A birthday counts from 00:00 UTC of the picked
  day and the public `age` moves at the 00:10 UTC run: 03:00–03:10 in
  Istanbul, on the day. West of UTC that moment falls on the previous evening
  by the member's own clock (17:00 in Los Angeles) — the right UTC day, hours
  ahead of their local midnight. This is unchanged; counting from the member's
  own midnight would need their time zone, which the server does not hold.
- An `age` the earlier rule already moved a day early stays one too high until
  the birthday itself (at most a day). Only data written by that rule is
  affected — emulator and QA suites; it was never deployed.
