/**
 * Daily Humor Evolution — pure rules, no Firestore.
 *
 * After the initial calibration, every eligible member gets the same short
 * daily set: ten moving items (video, or a provider GIF shown as an animated
 * image), in the same order, for the whole canonical day. The set is chosen
 * once, published once and never reshuffled; answering it teaches the same
 * lifetime profile the Humor Lab does, with the same rating semantics.
 *
 * Everything that decides *which* day it is, *which* items make the set and
 * *whether* a set is good enough to publish lives here, so it can be tested
 * without an emulator and so the callables cannot drift from it.
 */
import {HUMOR_CATEGORIES, type HumorCategory} from "./categories.js";
import {stableHash} from "./calibration.js";
import {isAllowedMediaUrl} from "./contentValidation.js";
import {canServeHumorContent} from "./moderation.js";
import {ratingWeight} from "./profile.js";
import type {HumorContentDoc, HumorRating} from "./types.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const DAY_ID = /^(\d{4})-(\d{2})-(\d{2})$/;

export const DAILY_HUMOR_CONFIG = {
  /** Items in one day's set. */
  setSize: 10,
  /**
   * The canonical day is one global calendar day, not each member's local
   * one: everyone must see the same set. It turns over at midnight at this
   * UTC offset — Europe/Istanbul, which has no DST — the same boundary daily
   * Picks already use (picks/config.ts `logicalDayUtcOffsetMinutes`).
   */
  canonicalUtcOffsetMinutes: 180,
  /** No primary category may fill more than this many slots of one set. */
  maxPerCategory: 2,
  /** A set must span at least this many of the eleven humor dimensions. */
  minDistinctCategories: 5,
  /**
   * Items used by the previous N published days are kept out of today's set.
   * Bounded, and relaxed one day at a time (N, N-1 … 0) only when the pool
   * cannot otherwise fill a valid set — a fresh repeat beats no set, but
   * padding with ineligible content never happens.
   */
  recentRepeatDays: 2,
  /** Most catalogue documents one selection reads. */
  poolScanLimit: 400,
  /** A "not ready" verdict is re-checked at most this often. */
  notReadyRecheckMs: 15 * 60 * 1000,
  /** Selector identity, stored on every manifest. */
  selector: "daily-v1",
  /** Manifest schema. */
  schema: 1,
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

// ---------------------------------------------------------------------------
// Member eligibility (pacing)
// ---------------------------------------------------------------------------

export type DailyLockedReason = "calibration_incomplete" | "starts_tomorrow";

/**
 * Whether a member gets today's set.
 *
 * - Calibration not finished (and no pre-calibration profile that already
 *   counts as ready): locked, `calibration_incomplete`.
 * - Calibration finished *today*: locked, `starts_tomorrow` — the first daily
 *   set is the day after calibration, so nobody rates 15 + 10 in one sitting.
 * - Finished on an earlier day, or a legacy ready profile with no completion
 *   stamp: eligible. Existing calibrated members never redo calibration.
 *
 * Missed days are simply missed: only today's set is ever offered.
 */
export function dailyEligibility(input: {
  ready: boolean;
  /** Calibration `completedAt` in ms, or null when unknown/absent. */
  completedAtMs: number | null;
  todayId: string;
}): {eligible: true} | {eligible: false; reason: DailyLockedReason} {
  if (!input.ready) {
    return {eligible: false, reason: "calibration_incomplete"};
  }
  if (input.completedAtMs !== null && canonicalDayId(input.completedAtMs) >= input.todayId) {
    return {eligible: false, reason: "starts_tomorrow"};
  }
  return {eligible: true};
}

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
// Content eligibility
// ---------------------------------------------------------------------------

const MOTION_PATH = /\.(webp|gif|mp4)$/i;

/**
 * Moving media: a real video, or a licensed provider GIF that is shown as an
 * animated image (GIPHY GIFs are stored as type "meme" with an animated WebP
 * or GIF rendition). Text cards and static images never qualify.
 */
export function isMotionContent(content: HumorContentDoc): boolean {
  if (content.type === "video") {
    return true;
  }
  if (content.type !== "meme" || content.source.type !== "licensed_api") {
    return false;
  }
  const url = content.media?.downloadUrl;
  if (typeof url !== "string") {
    return false;
  }
  try {
    return MOTION_PATH.test(new URL(url).pathname);
  } catch {
    return false;
  }
}

export type DailyIneligibleReason =
  | "not-servable"
  | "not-motion"
  | "media-unhealthy"
  | "qa-fixture"
  | "not-humor-relevant";

/** Why [content] may not be in a daily set, or null when it may. */
export function dailyIneligibility(content: HumorContentDoc): DailyIneligibleReason | null {
  if (!canServeHumorContent({active: content.active, safetyStatus: content.safetyStatus})) {
    return "not-servable";
  }
  if (content.sourceTrust === "qa_fixture") {
    return "qa-fixture";
  }
  if (!isMotionContent(content)) {
    return "not-motion";
  }
  if (!isAllowedMediaUrl(content.media?.downloadUrl ?? null)) {
    return "media-unhealthy";
  }
  const aspect = content.media?.aspectRatio;
  if (aspect != null && (!Number.isFinite(aspect) || aspect < 0.25 || aspect > 4)) {
    return "media-unhealthy";
  }
  // Humor-relevant: the item carries signal on its own primary dimension, so
  // a rating of it actually teaches the profile something.
  if (!((content.humorVector[content.category] ?? 0) > 0)) {
    return "not-humor-relevant";
  }
  return null;
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

type Candidate = {content: HumorContentDoc; rank: number; order: number};

/**
 * Non-anchor items first: every member meets some anchor items during
 * calibration, so a daily set built from them would mostly re-ask questions.
 * They stay eligible — they are used when the open pool runs short.
 */
function preferenceTier(content: HumorContentDoc): number {
  return content.calibration.slot === null ? 0 : 1;
}

function rankedCandidates(pool: readonly HumorContentDoc[], dayId: string): Candidate[] {
  return pool
    .map((content) => ({
      content,
      rank: preferenceTier(content),
      order: stableHash(`${DAILY_HUMOR_CONFIG.selector}|${dayId}|${content.contentId}`),
    }))
    .sort(
      (a, b) =>
        a.rank - b.rank ||
        a.order - b.order ||
        (a.content.contentId < b.content.contentId ? -1 : 1),
    );
}

/**
 * Greedy, deterministic fill: first one item per dimension in the day's
 * rotated dimension order (breadth), then up to `maxPerCategory` each.
 */
function fill(candidates: readonly Candidate[], dayId: string): HumorContentDoc[] {
  const size = DAILY_HUMOR_CONFIG.setSize;
  const picked: HumorContentDoc[] = [];
  const perCategory = new Map<HumorCategory, number>();
  const used = new Set<string>();
  const start = stableHash(`${DAILY_HUMOR_CONFIG.selector}|dims|${dayId}`) % HUMOR_CATEGORIES.length;
  const dimOrder = HUMOR_CATEGORIES.map(
    (_, i) => HUMOR_CATEGORIES[(start + i) % HUMOR_CATEGORIES.length],
  );
  const take = (candidate: Candidate): void => {
    picked.push(candidate.content);
    used.add(candidate.content.contentId);
    perCategory.set(
      candidate.content.category,
      (perCategory.get(candidate.content.category) ?? 0) + 1,
    );
  };
  for (const dim of dimOrder) {
    if (picked.length >= size) break;
    const first = candidates.find((c) => c.content.category === dim && !used.has(c.content.contentId));
    if (first) take(first);
  }
  for (const candidate of candidates) {
    if (picked.length >= size) break;
    if (used.has(candidate.content.contentId)) continue;
    if ((perCategory.get(candidate.content.category) ?? 0) >= DAILY_HUMOR_CONFIG.maxPerCategory) {
      continue;
    }
    take(candidate);
  }
  // Present in the day's shuffled order, not grouped by dimension, so the
  // sequence gives nothing away about what is being measured.
  const position = new Map(candidates.map((c) => [c.content.contentId, c.order]));
  return picked.sort(
    (a, b) =>
      (position.get(a.contentId) ?? 0) - (position.get(b.contentId) ?? 0) ||
      (a.contentId < b.contentId ? -1 : 1),
  );
}

export type DailySetProblem =
  | "wrong-size"
  | "duplicate-item"
  | "ineligible-item"
  | "category-cap"
  | "too-few-categories";

/** Pre-publication validation. Null when [items] may be published as a set. */
export function validateDailySet(items: readonly HumorContentDoc[]): DailySetProblem | null {
  if (items.length !== DAILY_HUMOR_CONFIG.setSize) {
    return "wrong-size";
  }
  if (new Set(items.map((i) => i.contentId)).size !== items.length) {
    return "duplicate-item";
  }
  if (items.some((i) => dailyIneligibility(i) !== null)) {
    return "ineligible-item";
  }
  const counts = new Map<string, number>();
  for (const item of items) {
    counts.set(item.category, (counts.get(item.category) ?? 0) + 1);
  }
  if ([...counts.values()].some((n) => n > DAILY_HUMOR_CONFIG.maxPerCategory)) {
    return "category-cap";
  }
  if (counts.size < DAILY_HUMOR_CONFIG.minDistinctCategories) {
    return "too-few-categories";
  }
  return null;
}

export type DailySelection =
  | {ok: true; items: HumorContentDoc[]; recentDaysExcluded: number; eligiblePoolSize: number}
  | {ok: false; reason: "insufficient-content"; eligiblePoolSize: number};

/**
 * Choose the set for [dayId] from [pool].
 *
 * Deterministic: the same pool and day always give the same ten items in the
 * same order. Not personalised — nothing about any member is an input.
 * `recentByDay[0]` holds the ids used yesterday, `[1]` the day before, …
 */
export function selectDailySet(input: {
  dayId: string;
  pool: readonly HumorContentDoc[];
  recentByDay: readonly (readonly string[])[];
}): DailySelection {
  const eligible = dedupe(input.pool).filter((c) => dailyIneligibility(c) === null);
  const window = Math.min(DAILY_HUMOR_CONFIG.recentRepeatDays, input.recentByDay.length);
  for (let days = window; days >= 0; days--) {
    const recent = new Set(input.recentByDay.slice(0, days).flat());
    const candidates = rankedCandidates(
      eligible.filter((c) => !recent.has(c.contentId)),
      input.dayId,
    );
    const items = fill(candidates, input.dayId);
    if (validateDailySet(items) === null) {
      return {ok: true, items, recentDaysExcluded: days, eligiblePoolSize: eligible.length};
    }
  }
  return {ok: false, reason: "insufficient-content", eligiblePoolSize: eligible.length};
}

/**
 * A replacement for slot [index] of an existing set: the best-ranked eligible
 * item not already in the set that keeps the set valid. Null when none does.
 */
export function selectRepairItem(input: {
  dayId: string;
  /** The set as published; the slot being replaced may be null (missing). */
  current: readonly (HumorContentDoc | null)[];
  index: number;
  pool: readonly HumorContentDoc[];
  version: number;
  /** Ids that must not come back (the item being replaced). */
  excludeIds?: readonly string[];
}): HumorContentDoc | null {
  const inSet = new Set([
    ...input.current.flatMap((c) => (c ? [c.contentId] : [])),
    ...(input.excludeIds ?? []),
  ]);
  const candidates = rankedCandidates(
    dedupe(input.pool).filter((c) => !inSet.has(c.contentId) && dailyIneligibility(c) === null),
    `${input.dayId}#repair${input.version}`,
  );
  for (const candidate of candidates) {
    const next = input.current.slice();
    next[input.index] = candidate.content;
    if (next.every((c) => c !== null) && validateDailySet(next as HumorContentDoc[]) === null) {
      return candidate.content;
    }
  }
  return null;
}

function dedupe(pool: readonly HumorContentDoc[]): HumorContentDoc[] {
  const seen = new Set<string>();
  return pool.filter((c) => (seen.has(c.contentId) ? false : (seen.add(c.contentId), true)));
}

// ---------------------------------------------------------------------------
// Member progress
// ---------------------------------------------------------------------------

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

/** Progress over a set of [total] slots given the answered ones. */
export function dailyProgress(answers: Map<number, DailyAnswer>, total: number): {
  answeredCount: number;
  completed: boolean;
  nextIndex: number;
} {
  let nextIndex = total;
  for (let i = 0; i < total; i++) {
    if (!answers.has(i)) {
      nextIndex = i;
      break;
    }
  }
  const answeredCount = Math.min(total, answers.size);
  return {answeredCount, completed: answeredCount >= total, nextIndex};
}

// ---------------------------------------------------------------------------
// Pairwise shared-response agreement
// ---------------------------------------------------------------------------

/** contentId → rating, rated daily answers only (skips never appear). */
export type DailyRatedAnswers = ReadonlyMap<string, HumorRating>;

/** Rated answers only, across any number of stored daily documents. */
export function ratedDailyAnswers(
  days: readonly {answers?: unknown; total?: unknown}[],
): Map<string, HumorRating> {
  const out = new Map<string, HumorRating>();
  for (const day of days) {
    const total = Number(day.total ?? DAILY_HUMOR_CONFIG.setSize) || DAILY_HUMOR_CONFIG.setSize;
    for (const answer of parseDailyAnswers(day.answers, total).values()) {
      if (!answer.skipped && answer.rating !== null) {
        out.set(answer.contentId, answer.rating);
      }
    }
  }
  return out;
}

/**
 * How closely two members rated the daily items they *both* rated.
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
