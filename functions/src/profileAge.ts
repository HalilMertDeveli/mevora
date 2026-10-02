import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type Firestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import {ageFromBirthDate, birthCalendarDate} from "./profileSafety.js";

/**
 * A member's date of birth and the age other members see.
 *
 * profiles/{uid} is readable by every signed-in member, so it carries the age
 * and nothing more precise. The date itself is private account data on
 * users/{uid}.birthDate, which only its owner can read. The owner's app writes
 * it there once (the rules refuse a change); everything derived from it is
 * written by the server:
 *
 *   profiles/{uid}.age           what members and matching read
 *   users/{uid}.ageRolloverAt    when that age next changes
 *
 * `ageRolloverAt` is what lets the daily roll-over find the members whose
 * birthday has come with one indexed query, instead of reading every account.
 * Because it is a moment rather than a calendar day, a run that was missed is
 * caught up by the next one. A marker that comes due before the birthday it
 * stands for — one written by an earlier version of the rule — is replaced by
 * the right one and the age is left alone, so no marker needs recomputing.
 */

/**
 * The member's date of birth: the private account's, or — for a profile
 * written before the date moved there and not yet backfilled — the copy still
 * on the profile. The account wins when both exist.
 */
export function memberBirthDate(
  account: DocumentData | undefined,
  profile: DocumentData | undefined,
): Timestamp | null {
  if (account?.birthDate instanceof Timestamp) {
    return account.birthDate;
  }
  if (profile?.birthDate instanceof Timestamp) {
    return profile.birthDate;
  }
  return null;
}

/**
 * The first moment after `now` at which ageFromBirthDate returns a higher
 * number: midnight UTC at the start of the next birthday. Built from the same
 * calendar day the age rule reads (birthCalendarDate), so the two cannot
 * disagree — a 29 February birthday lands on 1 March in a common year here
 * because it does there.
 */
export function nextAgeChangeAt(birthDate: Date, now: Date): Date {
  const born = birthCalendarDate(birthDate);
  const birthdayIn = (year: number) => new Date(Date.UTC(year, born.getUTCMonth(), born.getUTCDate()));
  const thisYear = birthdayIn(now.getUTCFullYear());
  return thisYear.getTime() > now.getTime() ? thisYear : birthdayIn(now.getUTCFullYear() + 1);
}

/** What users/{uid} holds about the member's birth: the date and the server's marker. */
export function accountBirthFields(birthDate: Timestamp, now: Date): {birthDate: Timestamp; ageRolloverAt: Timestamp} {
  return {
    birthDate,
    ageRolloverAt: Timestamp.fromDate(nextAgeChangeAt(birthDate.toDate(), now)),
  };
}

export interface AgeRolloverResult {
  /** Accounts whose marker had come due. */
  due: number;
  /** Profiles whose age was rewritten. */
  updated: number;
  /** Due accounts whose profile already showed the right age, or had no profile. */
  unchanged: number;
  /** Markers removed from accounts with no readable date of birth. */
  cleared: number;
  failed: number;
}

/**
 * Brings profiles/{uid}.age up to date for every member whose birthday has
 * arrived, and schedules each one's next change.
 *
 * Costs one query read per due member, one profile read, and at most two
 * writes — once a year per member. A profile whose age is already right is not
 * rewritten, and `updatedAt` is left alone: this is not an edit by the member.
 */
export async function rollOverProfileAges(
  db: Firestore,
  options: {now?: Date; pageSize?: number; maxMembers?: number} = {},
): Promise<AgeRolloverResult> {
  const now = options.now ?? new Date();
  const pageSize = options.pageSize ?? 200;
  const maxMembers = options.maxMembers ?? 2000;
  const result: AgeRolloverResult = {due: 0, updated: 0, unchanged: 0, cleared: 0, failed: 0};

  let cursor: QueryDocumentSnapshot | null = null;
  while (result.due < maxMembers) {
    let query = db
      .collection("users")
      .where("ageRolloverAt", "<=", Timestamp.fromDate(now))
      .orderBy("ageRolloverAt")
      .limit(Math.min(pageSize, maxMembers - result.due));
    if (cursor) {
      query = query.startAfter(cursor);
    }
    const page = await query.get();
    if (page.empty) {
      break;
    }
    for (const account of page.docs) {
      result.due += 1;
      try {
        const outcome = await rollOverOne(db, account, now);
        result[outcome] += 1;
      } catch {
        // Typically an account deleted between the query and the write. The
        // cursor moves past it; a marker that still exists is seen next run.
        result.failed += 1;
      }
    }
    cursor = page.docs[page.docs.length - 1];
    if (page.docs.length < pageSize) {
      break;
    }
  }
  return result;
}

async function rollOverOne(
  db: Firestore,
  account: QueryDocumentSnapshot,
  now: Date,
): Promise<"updated" | "unchanged" | "cleared"> {
  const birthDate = account.get("birthDate");
  if (!(birthDate instanceof Timestamp)) {
    await account.ref.update({ageRolloverAt: FieldValue.delete()});
    return "cleared";
  }
  const age = ageFromBirthDate(birthDate.toDate(), now);
  const profileRef = db.doc(`profiles/${account.id}`);
  const profile = await profileRef.get();
  const batch = db.batch();
  const stale = profile.exists && profile.get("age") !== age;
  if (stale) {
    batch.update(profileRef, {age});
  }
  batch.update(account.ref, {ageRolloverAt: accountBirthFields(birthDate, now).ageRolloverAt});
  await batch.commit();
  return stale ? "updated" : "unchanged";
}

export interface BirthDateMoveResult {
  /** Profiles found still holding a date of birth. */
  examined: number;
  /** Of those, how many have (or, in a dry run, would have) the date moved to the account. */
  moved: number;
  /** Of those, how many accounts already held a date, which was kept. */
  alreadyOnAccount: number;
  /** Profiles with no users/{uid} document. Left untouched unless `stripOrphans`. */
  orphans: string[];
  /** Profiles actually rewritten. Always 0 in a dry run. */
  written: number;
}

// Range filters match one value type, so this skips the `birthDate: null`
// that older app builds write, and anything that is not a timestamp.
const EARLIEST_BIRTH_DATE = Timestamp.fromDate(new Date(Date.UTC(1900, 0, 1)));

/**
 * One-off backfill: takes the date of birth off every profile written before
 * it moved to the private account.
 *
 * For each such profile, in one transaction: the account receives the date
 * (unless it already holds one — that one is kept) and its roll-over marker,
 * and the profile loses `birthDate` and gets the current `age`. Nothing else
 * on either document is touched. A profile with no account document is
 * reported and left as it is; with `stripOrphans` its date is removed and its
 * age refreshed, and no account is created for it.
 *
 * Safe to stop and re-run: a processed profile no longer matches the query.
 */
export async function moveProfileBirthDates(
  db: Firestore,
  options: {confirm: boolean; now?: Date; limit?: number; pageSize?: number; stripOrphans?: boolean},
): Promise<BirthDateMoveResult> {
  const now = options.now ?? new Date();
  const limit = options.limit ?? Number.POSITIVE_INFINITY;
  const pageSize = options.pageSize ?? 200;
  const result: BirthDateMoveResult = {examined: 0, moved: 0, alreadyOnAccount: 0, orphans: [], written: 0};

  let cursor: QueryDocumentSnapshot | null = null;
  while (result.examined < limit) {
    let query = db
      .collection("profiles")
      .where("birthDate", ">=", EARLIEST_BIRTH_DATE)
      .orderBy("birthDate")
      .limit(Math.min(pageSize, limit - result.examined));
    if (cursor) {
      query = query.startAfter(cursor);
    }
    const page = await query.get();
    if (page.empty) {
      break;
    }
    for (const found of page.docs) {
      result.examined += 1;
      const uid = found.id;
      const outcome = await db.runTransaction(async (tx) => {
        const profileRef = db.doc(`profiles/${uid}`);
        const accountRef = db.doc(`users/${uid}`);
        const [profile, account] = await Promise.all([tx.get(profileRef), tx.get(accountRef)]);
        const onProfile = profile.get("birthDate");
        if (!profile.exists || !(onProfile instanceof Timestamp)) {
          return "gone" as const;
        }
        if (!account.exists && !options.stripOrphans) {
          return "orphan" as const;
        }
        const birthDate = memberBirthDate(account.data(), profile.data()) as Timestamp;
        if (options.confirm) {
          tx.update(profileRef, {
            birthDate: FieldValue.delete(),
            age: ageFromBirthDate(birthDate.toDate(), now),
          });
          if (account.exists) {
            tx.update(accountRef, accountBirthFields(birthDate, now));
          }
        }
        if (!account.exists) {
          return "orphan" as const;
        }
        return account.get("birthDate") instanceof Timestamp ? ("kept" as const) : ("moved" as const);
      });
      if (outcome === "gone") {
        continue;
      }
      if (outcome === "orphan") {
        result.orphans.push(uid);
        if (options.confirm && options.stripOrphans) {
          result.written += 1;
        }
        continue;
      }
      if (outcome === "moved") {
        result.moved += 1;
      } else {
        result.alreadyOnAccount += 1;
      }
      if (options.confirm) {
        result.written += 1;
      }
    }
    cursor = page.docs[page.docs.length - 1];
    if (page.docs.length < pageSize) {
      break;
    }
  }
  return result;
}
