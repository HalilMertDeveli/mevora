import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {isAccountEligible} from "../profileSafety.js";
import {dayKeyFor, normalizeOffsetMinutes} from "./day.js";
import {applyCheckIn, parseCounters, type CheckInStatus} from "./rules.js";

/** Response contract version. Bump when a field changes meaning. */
export const STREAK_SCHEMA_VERSION = 1;

/**
 * The member's own streak. Server-owned: no Firestore rule grants a client
 * read or write here (the catch-all deny covers it), and the only writer is
 * {@link recordCheckIn}.
 */
export function dailyStreakDocPath(uid: string): string {
  return `users/${uid}/dailyStreak/current`;
}

export type CheckInResponse = {
  schemaVersion: number;
  status: CheckInStatus | "ineligible";
  credited: boolean;
  currentStreak: number;
  longestStreak: number;
  totalCheckInDays: number;
  /** The member's local day this call was evaluated for, `YYYY-MM-DD`. */
  dayKey: string;
  newPersonalBest: boolean;
  milestone: boolean;
};

function flag(value: unknown): boolean {
  return value === true;
}

function onboardingDone(data: DocumentData | undefined): boolean {
  return flag(data?.onboardingCompleted) || flag(data?.profileCompleted);
}

/**
 * Whether this account is a member who can be in the app — the same reading
 * the client's router makes (`onboardingCompleted || profileCompleted`, on
 * either the account or the profile document), plus the server's account
 * standing check. A missing account document is not a member: after a
 * deletion it is gone, and a streak must not be created for it.
 */
function isStreakEligible(
  account: DocumentData | undefined,
  profile: DocumentData | undefined,
): boolean {
  if (!account || !isAccountEligible(account)) {
    return false;
  }
  return onboardingDone(account) || onboardingDone(profile);
}

export type CheckInInput = {
  uid: string;
  /** The client's UTC offset in minutes. Untrusted; normalised here. */
  timezoneOffsetMinutes: unknown;
  /** Trusted server time. Injectable for tests only. */
  nowMs?: number;
};

/**
 * Records one eligible visit and returns the resulting streak.
 *
 * One transaction reads the account and the streak (and the profile only when
 * the account alone does not show onboarding finished), so the eligibility
 * decision and the write are atomic: an account deleted or suspended mid-call
 * cannot end up with a streak written after the fact.
 *
 * Idempotent per local day. A same-day call writes nothing at all — not even
 * `updatedAt` — so reopening the app costs reads, never writes. Two calls
 * racing on a new day are serialised by the transaction; the loser retries,
 * sees the day already recorded and reports `alreadyCounted`. Even without
 * that serialisation the write is of absolute values, so a replay converges
 * on the same document instead of adding a second day.
 */
export async function recordCheckIn(db: Firestore, input: CheckInInput): Promise<CheckInResponse> {
  const {uid} = input;
  const nowMs = input.nowMs ?? Date.now();
  const accountRef = db.doc(`users/${uid}`);
  const profileRef = db.doc(`profiles/${uid}`);
  const streakRef = db.doc(dailyStreakDocPath(uid));

  return db.runTransaction(async (tx) => {
    const [accountSnap, streakSnap] = await tx.getAll(accountRef, streakRef);
    const account = accountSnap.exists ? accountSnap.data() : undefined;
    const stored = streakSnap.exists ? streakSnap.data() : undefined;

    // A client that sends no usable offset keeps whatever zone it last had.
    const offset =
      normalizeOffsetMinutes(input.timezoneOffsetMinutes) ??
      normalizeOffsetMinutes(stored?.lastTimezoneOffsetMinutes) ??
      0;
    const dayKey = dayKeyFor(nowMs, offset);

    let profile: DocumentData | undefined;
    if (account && isAccountEligible(account) && !onboardingDone(account)) {
      const profileSnap = await tx.get(profileRef);
      profile = profileSnap.exists ? profileSnap.data() : undefined;
    }
    if (!isStreakEligible(account, profile)) {
      return {
        schemaVersion: STREAK_SCHEMA_VERSION,
        status: "ineligible",
        credited: false,
        currentStreak: 0,
        longestStreak: 0,
        totalCheckInDays: 0,
        dayKey,
        newPersonalBest: false,
        milestone: false,
      };
    }

    const transition = applyCheckIn(parseCounters(stored), dayKey);
    if (transition.credited) {
      const now = FieldValue.serverTimestamp();
      tx.set(streakRef, {
        schemaVersion: STREAK_SCHEMA_VERSION,
        currentStreak: transition.next.currentStreak,
        longestStreak: transition.next.longestStreak,
        totalCheckInDays: transition.next.totalCheckInDays,
        lastCheckInDay: transition.next.lastCheckInDay,
        lastCheckInAt: now,
        lastTimezoneOffsetMinutes: offset,
        createdAt: stored?.createdAt ?? now,
        updatedAt: now,
      });
    }
    return {
      schemaVersion: STREAK_SCHEMA_VERSION,
      status: transition.status,
      credited: transition.credited,
      currentStreak: transition.next.currentStreak,
      longestStreak: transition.next.longestStreak,
      totalCheckInDays: transition.next.totalCheckInDays,
      // The day the stored streak stands on. Same as the evaluated day except
      // in the date-line case, where the stored day is the later one.
      dayKey: transition.next.lastCheckInDay ?? dayKey,
      newPersonalBest: transition.newPersonalBest,
      milestone: transition.milestone,
    };
  });
}

/** Privacy export view: the counters only, no timestamps beyond the day. */
export function streakExportView(data: DocumentData | undefined): Record<string, unknown> | null {
  if (!data) {
    return null;
  }
  const counters = parseCounters(data);
  return {
    currentStreak: counters.currentStreak,
    longestStreak: counters.longestStreak,
    totalCheckInDays: counters.totalCheckInDays,
    lastCheckInDay: counters.lastCheckInDay,
  };
}
