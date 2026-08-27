import type {StreakRewardDef} from "./matchingStreakEngine.js";

/**
 * Configurable Matching Streak rewards.
 * Add / reorder / change thresholds here — do not hard-code grants in engine callers.
 */
export const MATCHING_STREAK_REWARDS: readonly StreakRewardDef[] = [
  {
    id: "streak_7_profile_badge",
    minDays: 7,
    type: "profile_badge",
    payload: {badgeId: "matching_streak_7"},
  },
  {
    id: "streak_14_compatibility_insight",
    minDays: 14,
    type: "compatibility_insight",
    payload: {},
  },
  {
    id: "streak_30_boost_discount",
    minDays: 30,
    type: "boost_discount",
    payload: {percentOff: 20},
  },
];

/** Local hour (Europe/Istanbul) when streak reminder may fire. */
export const MATCHING_STREAK_REMINDER_HOUR_ISTANBUL = 20;
