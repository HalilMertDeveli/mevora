import {daysBetween, isDayKey} from "./day.js";

/** Streak lengths that get a stronger celebration on the client. */
export const STREAK_MILESTONES: readonly number[] = [3, 7, 14, 30, 60, 100];

export type StreakCounters = {
  currentStreak: number;
  longestStreak: number;
  totalCheckInDays: number;
  lastCheckInDay: string | null;
};

export type CheckInStatus = "started" | "continued" | "reset" | "alreadyCounted";

export type CheckInTransition = {
  status: CheckInStatus;
  /** True when this call awarded a new streak day. */
  credited: boolean;
  next: StreakCounters;
  newPersonalBest: boolean;
  milestone: boolean;
};

function count(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

/**
 * Reads stored streak counters defensively. A missing or malformed document
 * reads as "no streak yet"; a malformed field reads as zero rather than
 * poisoning the arithmetic.
 */
export function parseCounters(data: Record<string, unknown> | undefined): StreakCounters {
  if (!data) {
    return {currentStreak: 0, longestStreak: 0, totalCheckInDays: 0, lastCheckInDay: null};
  }
  const currentStreak = count(data.currentStreak);
  return {
    currentStreak,
    longestStreak: Math.max(count(data.longestStreak), currentStreak),
    totalCheckInDays: count(data.totalCheckInDays),
    lastCheckInDay: isDayKey(data.lastCheckInDay) ? data.lastCheckInDay : null,
  };
}

/**
 * The streak after an eligible visit on [today].
 *
 * - no previous day            → started, streak 1
 * - same day (or earlier)      → alreadyCounted, nothing changes
 * - exactly the next day       → continued, streak + 1
 * - one or more days skipped   → reset, streak 1, longest kept
 *
 * "Earlier" happens only when a member moves west across the date line after
 * checking in; treating it as already counted keeps the stored day from ever
 * moving backwards.
 *
 * Counters are always absolute values derived from what was read, never
 * increments, so the same transition applied twice lands on the same state.
 */
export function applyCheckIn(previous: StreakCounters, today: string): CheckInTransition {
  const last = previous.lastCheckInDay;
  const gap = last === null ? null : daysBetween(last, today);

  if (gap !== null && gap <= 0) {
    return {
      status: "alreadyCounted",
      credited: false,
      next: previous,
      newPersonalBest: false,
      milestone: false,
    };
  }

  const status: CheckInStatus = gap === null
    ? "started"
    : gap === 1 && previous.currentStreak > 0
      ? "continued"
      : "reset";
  const currentStreak = status === "continued" ? previous.currentStreak + 1 : 1;
  const longestStreak = Math.max(previous.longestStreak, currentStreak);
  return {
    status,
    credited: true,
    next: {
      currentStreak,
      longestStreak,
      totalCheckInDays: previous.totalCheckInDays + 1,
      lastCheckInDay: today,
    },
    // Beating a record you already held. A first ever day is a start, not a
    // record, and a restart can never exceed the longest.
    newPersonalBest: status === "continued" && currentStreak > previous.longestStreak,
    milestone: STREAK_MILESTONES.includes(currentStreak),
  };
}
