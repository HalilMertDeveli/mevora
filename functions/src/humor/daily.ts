/**
 * Humor day — pure rules, no Firestore.
 *
 * The canonical day every humor rule runs on, and the pairwise agreement over
 * items two members both rated. Which items a member gets on a day is decided
 * by the Core sequence (`coreSchedule.ts`); the global, algorithmically
 * selected daily set this file used to build is gone.
 */
import {ratingWeight} from "./profile.js";
import type {HumorRating} from "./types.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const DAY_ID = /^(\d{4})-(\d{2})-(\d{2})$/;

export const DAILY_HUMOR_CONFIG = {
  /**
   * The canonical day is one global calendar day, not each member's local
   * one. It turns over at midnight at this UTC offset — Europe/Istanbul, which
   * has no DST — the same boundary daily Picks (picks/config.ts
   * `logicalDayUtcOffsetMinutes`) and the relationship questions use.
   */
  canonicalUtcOffsetMinutes: 180,
  /** Shared rated items needed before a pairwise agreement means anything. */
  minSharedForAgreement: 3,
} as const;

// ---------------------------------------------------------------------------
// Canonical day
// ---------------------------------------------------------------------------

/** The canonical day (`YYYY-MM-DD`) containing [nowMs]. */
export function canonicalDayId(nowMs: number): string {
  const shifted = nowMs + DAILY_HUMOR_CONFIG.canonicalUtcOffsetMinutes * 60_000;
  return new Date(shifted).toISOString().slice(0, 10);
}

/** When the canonical day containing [nowMs] ends. */
export function nextCanonicalDayStartMs(nowMs: number): number {
  const offsetMs = DAILY_HUMOR_CONFIG.canonicalUtcOffsetMinutes * 60_000;
  return Math.floor((nowMs + offsetMs) / DAY_MS) * DAY_MS + DAY_MS - offsetMs;
}

/** True for a well-formed `YYYY-MM-DD` naming a real date. */
export function isDayId(value: unknown): value is string {
  if (typeof value !== "string") {
    return false;
  }
  const match = DAY_ID.exec(value);
  if (!match) {
    return false;
  }
  const ms = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return new Date(ms).toISOString().slice(0, 10) === value;
}

/** [dayId] moved by [days] calendar days. */
export function shiftDayId(dayId: string, days: number): string {
  const match = DAY_ID.exec(dayId);
  if (!match) {
    throw new Error(`not a day id: ${dayId}`);
  }
  const ms = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return new Date(ms + days * DAY_MS).toISOString().slice(0, 10);
}

/**
 * Why a member has no daily Core set right now.
 *
 * - `calibration_incomplete`: the initial fifteen are still open.
 * - `starts_tomorrow`: the initial fifteen were finished today (or today is
 *   already spent) — the daily five begin on the next logical day.
 * - `sequence_complete`: every entry of the sequence is behind them.
 */
export type DailyLockedReason =
  | "calibration_incomplete"
  | "starts_tomorrow"
  | "sequence_complete";

/** Milliseconds from a Firestore Timestamp, a Date or a number; else null. */
export function timestampMs(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (value && typeof value === "object") {
    const candidate = value as {toMillis?: () => number; seconds?: unknown; _seconds?: unknown};
    if (typeof candidate.toMillis === "function") {
      return candidate.toMillis();
    }
    const seconds = candidate.seconds ?? candidate._seconds;
    if (typeof seconds === "number") {
      return seconds * 1000;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Stored day answers (the documents the old daily set wrote)
// ---------------------------------------------------------------------------

/** Most slots one stored day can hold; only bounds the parse. */
const MAX_STORED_SLOTS = 100;

export type DailyAnswer = {
  contentId: string;
  /** Null only for a `media_failed` skip. */
  rating: HumorRating | null;
  skipped: boolean;
};

/** Answered slots keyed by index, parsed defensively from the stored map. */
export function parseDailyAnswers(raw: unknown, total: number): Map<number, DailyAnswer> {
  const out = new Map<number, DailyAnswer>();
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return out;
  }
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    const index = Number(key);
    if (!Number.isInteger(index) || index < 0 || index >= total) continue;
    if (!value || typeof value !== "object") continue;
    const v = value as Record<string, unknown>;
    if (typeof v.contentId !== "string") continue;
    out.set(index, {
      contentId: v.contentId,
      rating: typeof v.rating === "string" ? (v.rating as HumorRating) : null,
      skipped: v.skipped === true,
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Pairwise shared-response agreement
// ---------------------------------------------------------------------------

/** contentId → rating, rated daily answers only (skips never appear). */
export type DailyRatedAnswers = ReadonlyMap<string, HumorRating>;

/** Rated answers only, across any number of stored daily documents. */
export function ratedDailyAnswers(
  days: readonly {answers?: unknown}[],
): Map<string, HumorRating> {
  const out = new Map<string, HumorRating>();
  for (const day of days) {
    for (const answer of parseDailyAnswers(day.answers, MAX_STORED_SLOTS).values()) {
      if (!answer.skipped && answer.rating !== null) {
        out.set(answer.contentId, answer.rating);
      }
    }
  }
  return out;
}

/**
 * How closely two members rated the items they *both* rated.
 *
 * Only shared content ids count; an item one side skipped or never saw is not
 * treated as neutral — it is simply not evidence. Per shared item the
 * agreement is `1 - |wA - wB| / 2` over the rating weights (−1 … 1), so it is
 * bounded in [0, 1]; the result is the mean, as a whole number 0 … 100. Below
 * `minSharedForAgreement` shared items there is no score (`null`).
 *
 * Deterministic arithmetic, no model. It is a standalone signal: nothing in
 * Discover ranking or the main compatibility weights reads it.
 */
export function dailyResponseAgreement(
  a: DailyRatedAnswers,
  b: DailyRatedAnswers,
): {sharedDailyItemCount: number; dailyResponseAgreement: number | null} {
  let shared = 0;
  let sum = 0;
  for (const [contentId, ratingA] of a) {
    const ratingB = b.get(contentId);
    if (ratingB === undefined) continue;
    shared += 1;
    sum += 1 - Math.abs(ratingWeight(ratingA) - ratingWeight(ratingB)) / 2;
  }
  if (shared < DAILY_HUMOR_CONFIG.minSharedForAgreement) {
    return {sharedDailyItemCount: shared, dailyResponseAgreement: null};
  }
  const score = Math.round((100 * sum) / shared);
  return {
    sharedDailyItemCount: shared,
    dailyResponseAgreement: Math.min(100, Math.max(0, score)),
  };
}
