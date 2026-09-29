/**
 * Calendar-day arithmetic for the daily streak.
 *
 * The server's clock is the only clock that decides which day it is. The
 * client contributes its UTC offset so the day boundary falls at the member's
 * local midnight rather than at UTC midnight — without it a member in Istanbul
 * would see their day roll over at 03:00. An offset can move the day by at most
 * one either way from the UTC day, which is the whole of what a lying client
 * can gain; a streak has no monetary value, so that is accepted rather than
 * policed.
 */

/** UTC−12:00 — the westernmost offset in use. */
export const MIN_OFFSET_MINUTES = -12 * 60;
/** UTC+14:00 — the easternmost offset in use (Line Islands). */
export const MAX_OFFSET_MINUTES = 14 * 60;

const DAY_MS = 24 * 60 * 60 * 1000;
const DAY_KEY = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * A usable offset in minutes, or null when [raw] is not one.
 *
 * Out-of-range values are clamped rather than rejected: a device reporting
 * UTC+15 is wrong, not hostile, and the nearest real offset is the kindest
 * reading of it.
 */
export function normalizeOffsetMinutes(raw: unknown): number | null {
  if (typeof raw !== "number" || !Number.isFinite(raw)) {
    return null;
  }
  const rounded = Math.round(raw);
  return Math.min(MAX_OFFSET_MINUTES, Math.max(MIN_OFFSET_MINUTES, rounded));
}

/** The local calendar day, as `YYYY-MM-DD`, at [nowMs] in a zone [offsetMinutes] from UTC. */
export function dayKeyFor(nowMs: number, offsetMinutes: number): string {
  return new Date(nowMs + offsetMinutes * 60 * 1000).toISOString().slice(0, 10);
}

/** True for a well-formed `YYYY-MM-DD` that names a real date. */
export function isDayKey(value: unknown): value is string {
  if (typeof value !== "string") {
    return false;
  }
  const match = DAY_KEY.exec(value);
  if (!match) {
    return false;
  }
  const ms = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return new Date(ms).toISOString().slice(0, 10) === value;
}

function dayNumber(dayKey: string): number {
  const match = DAY_KEY.exec(dayKey);
  if (!match) {
    throw new Error(`not a day key: ${dayKey}`);
  }
  return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) / DAY_MS;
}

/** Whole calendar days from [from] to [to]; negative when [to] is earlier. */
export function daysBetween(from: string, to: string): number {
  return dayNumber(to) - dayNumber(from);
}
