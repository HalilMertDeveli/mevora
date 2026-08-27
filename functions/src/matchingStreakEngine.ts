/** Pure Matching Streak rules. Days use Europe/Istanbul calendar keys (YYYY-MM-DD). */

export const MATCHING_STREAK_TIMEZONE = "Europe/Istanbul";

export type MatchingStreakState = {
  currentStreak: number;
  longestStreak: number;
  lastParticipatedDay: string | null;
  lastRoundId: string | null;
  unlockedRewardIds: string[];
};

export type StreakRewardDef = {
  id: string;
  minDays: number;
  type: string;
  payload?: Record<string, unknown>;
};

export type ParticipationResult = {
  state: MatchingStreakState;
  dayKey: string;
  alreadyParticipatedToday: boolean;
  newlyUnlocked: StreakRewardDef[];
};

export function emptyMatchingStreakState(): MatchingStreakState {
  return {
    currentStreak: 0,
    longestStreak: 0,
    lastParticipatedDay: null,
    lastRoundId: null,
    unlockedRewardIds: [],
  };
}

/** Istanbul calendar day key YYYY-MM-DD. */
export function istanbulDayKey(now: Date = new Date()): string {
  const parts = istanbulDateParts(now);
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function istanbulDateParts(now: Date): {
  year: string;
  month: string;
  day: string;
  hour: string;
} {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: MATCHING_STREAK_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  });
  const bag: Record<string, string> = {};
  for (const part of dtf.formatToParts(now)) {
    if (part.type !== "literal") bag[part.type] = part.value;
  }
  let hour = bag.hour ?? "00";
  if (hour === "24") hour = "00";
  return {
    year: bag.year ?? "1970",
    month: bag.month ?? "01",
    day: bag.day ?? "01",
    hour: hour.padStart(2, "0"),
  };
}

/** Previous Istanbul calendar day for a YYYY-MM-DD key. */
export function previousIstanbulDayKey(dayKey: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dayKey);
  if (!m) {
    throw new Error(`invalid-day-key:${dayKey}`);
  }
  // Noon-ish UTC avoids edge cases; Istanbul is fixed UTC+3.
  const noonUtc = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 9, 0, 0);
  return istanbulDayKey(new Date(noonUtc - 24 * 60 * 60 * 1000));
}

/**
 * Streak shown to the user "today".
 * Same day or consecutive yesterday → keep stored streak.
 * Missed a full Istanbul day → 0 until next participation.
 */
export function effectiveStreak(
  state: MatchingStreakState,
  todayKey: string = istanbulDayKey(),
): number {
  const last = state.lastParticipatedDay;
  if (!last || state.currentStreak <= 0) return 0;
  if (last === todayKey) return state.currentStreak;
  if (last === previousIstanbulDayKey(todayKey)) return state.currentStreak;
  return 0;
}

export function dailyParticipation(
  state: MatchingStreakState,
  todayKey: string = istanbulDayKey(),
): boolean {
  return state.lastParticipatedDay === todayKey;
}

/**
 * Apply one Match Game participation for an Istanbul day.
 * Max +1 streak per day regardless of how many rounds.
 */
export function applyParticipation(options: {
  state: MatchingStreakState;
  dayKey: string;
  roundId: string;
  rewards: readonly StreakRewardDef[];
}): ParticipationResult {
  const {state, dayKey, roundId, rewards} = options;
  if (state.lastParticipatedDay === dayKey) {
    return {
      state: {
        ...state,
        lastRoundId: roundId || state.lastRoundId,
      },
      dayKey,
      alreadyParticipatedToday: true,
      newlyUnlocked: [],
    };
  }

  const prev = previousIstanbulDayKey(dayKey);
  const nextStreak =
    state.lastParticipatedDay === prev ? state.currentStreak + 1 : 1;
  const longest = Math.max(state.longestStreak, nextStreak);
  const unlocked = new Set(state.unlockedRewardIds);
  const newlyUnlocked: StreakRewardDef[] = [];
  for (const reward of rewards) {
    if (reward.minDays <= nextStreak && !unlocked.has(reward.id)) {
      unlocked.add(reward.id);
      newlyUnlocked.push(reward);
    }
  }

  return {
    state: {
      currentStreak: nextStreak,
      longestStreak: longest,
      lastParticipatedDay: dayKey,
      lastRoundId: roundId || state.lastRoundId,
      unlockedRewardIds: [...unlocked],
    },
    dayKey,
    alreadyParticipatedToday: false,
    newlyUnlocked,
  };
}
