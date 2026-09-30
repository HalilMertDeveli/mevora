import {createHash} from "node:crypto";
import {
  LEGACY_BATCH_SIZING,
  PICKS_CONFIG,
  PICKS_SCHEMA_VERSION,
  PICKS_SIZING,
  type PicksSizing,
} from "./config.js";
import {isPickType} from "./categories.js";
import type {ComposedPick, PickReason, PickType} from "./types.js";

/**
 * The Picks batch lifecycle, as pure transitions over the stored document
 * `users/{uid}/mevoraPicks/current`.
 *
 * Daily: a batch lives until the next logical-day boundary (see
 * `logicalDayUtcOffsetMinutes`), whenever in the day it was made.
 *
 *   active ──like──▶ liked      (never returns; canonical like state)
 *   active ──pass──▶ passed     (never returns; canonical pass state)
 *   active ──match─▶ matched
 *   active ──block / delete / hide / out of range──▶ ineligible
 *   active ──batch expires undecided──▶ cooldown for `expiredCooldownMs`
 *
 * Opening a profile is not a transition: the Pick stays active.
 *
 * Only ids, codes and numbers are stored — never another member's profile
 * content. Names and photos are read fresh on every request.
 */

export type PickState = "active" | "liked" | "passed" | "matched" | "ineligible";
export type PickDecision = "liked" | "passed" | "matched";

/**
 * The numbers a Pick card shows, frozen with the Pick so a batch reads the
 * same on every visit. Scores and counts only.
 */
export interface PickCardSnapshot {
  compatibilityScore: number;
  compatibilityBreakdown: Record<string, number | null>;
  relationshipCompatibilityScore: number | null;
  relationshipSharedViewCount: number | null;
  relationshipAlignedCount: number | null;
  relationshipSummaryTopics: string[];
  musicCompatibilityScore: number | null;
  sharedMusicArtistCount: number;
  sharedMusicTrackCount: number;
  sharedMusicGenreCount: number;
  humorCompatibilityScore: number | null;
  sharedHumorTraits: string[];
}

export interface StoredPick {
  candidateUid: string;
  /** Opaque id for analytics joins. Not derivable back to the candidate. */
  pickId: string;
  rank: number;
  pickType: PickType;
  labels: PickType[];
  reasons: PickReason[];
  overallScore: number;
  isBoosted: boolean;
  /** See ComposedPick.selectionStrategy. Kept for a future Unexpected Match. */
  selectionStrategy: "exploit" | "explore";
  state: PickState;
  deliveredAtMs: number;
  decidedAtMs: number | null;
  card: PickCardSnapshot;
}

export interface PicksBatch {
  schemaVersion: number;
  generationId: string;
  generatedAtMs: number;
  refreshAtMs: number;
  /** Last time the pool was scanned for this batch (generation or top-up). */
  lastScanAtMs: number;
  /** Picks this batch has delivered in total, replacements included. */
  deliveredCount: number;
  /**
   * The day's size, fixed when the batch is generated: how many Picks it aims
   * for and the most it may ever deliver, replacements included. A config
   * change applies from the next batch, never to one already being shown.
   */
  targetCount: number;
  maxDeliveredCount: number;
  picks: StoredPick[];
  /** candidateUid → epoch ms until which they may not be picked again. */
  cooldowns: Record<string, number>;
  /**
   * Every candidate uid this document mentions (picks and cooldowns), so an
   * account deletion can find and scrub it with one array-contains query.
   */
  candidateUids: string[];
}

export function pickIdFor(generationId: string, candidateUid: string): string {
  return createHash("sha256").update(`${generationId}:${candidateUid}`).digest("hex").slice(0, 20);
}

function finiteOr(value: unknown, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

const PICK_STATES: readonly PickState[] = ["active", "liked", "passed", "matched", "ineligible"];

/**
 * Reads a stored batch defensively. Anything malformed, or from another
 * schema version, reads as "no batch" — a fresh one is generated rather than
 * trusting a shape this code did not write.
 */
export function parseBatch(raw: unknown): PicksBatch | null {
  if (!raw || typeof raw !== "object") return null;
  const data = raw as Record<string, unknown>;
  if (data.schemaVersion !== PICKS_SCHEMA_VERSION) return null;
  if (typeof data.generationId !== "string" || !data.generationId) return null;
  const picks: StoredPick[] = [];
  for (const entry of Array.isArray(data.picks) ? data.picks : []) {
    if (!entry || typeof entry !== "object") continue;
    const p = entry as Record<string, unknown>;
    if (typeof p.candidateUid !== "string" || !p.candidateUid || !isPickType(p.pickType)) continue;
    const state = PICK_STATES.includes(p.state as PickState) ? (p.state as PickState) : "ineligible";
    picks.push({
      candidateUid: p.candidateUid,
      pickId: typeof p.pickId === "string" ? p.pickId : pickIdFor(data.generationId, p.candidateUid),
      rank: finiteOr(p.rank, picks.length),
      pickType: p.pickType,
      labels: Array.isArray(p.labels) ? p.labels.filter(isPickType) : [p.pickType],
      reasons: Array.isArray(p.reasons) ? (p.reasons as PickReason[]) : [],
      overallScore: finiteOr(p.overallScore, 0),
      isBoosted: p.isBoosted === true,
      selectionStrategy: p.selectionStrategy === "explore" ? "explore" : "exploit",
      state,
      deliveredAtMs: finiteOr(p.deliveredAtMs, 0),
      decidedAtMs: p.decidedAtMs == null ? null : finiteOr(p.decidedAtMs, 0),
      card: (p.card ?? {}) as PickCardSnapshot,
    });
  }
  const cooldowns: Record<string, number> = {};
  if (data.cooldowns && typeof data.cooldowns === "object") {
    for (const [uid, until] of Object.entries(data.cooldowns as Record<string, unknown>)) {
      const ms = Number(until);
      if (uid && Number.isFinite(ms)) cooldowns[uid] = ms;
    }
  }
  const generatedAtMs = finiteOr(data.generatedAtMs, 0);
  const sized = Number.isFinite(Number(data.targetCount)) && Number(data.targetCount) > 0;
  const targetCount = sized ? Number(data.targetCount) : LEGACY_BATCH_SIZING.targetCount;
  const maxDeliveredCount = sized
    ? Math.max(targetCount, finiteOr(data.maxDeliveredCount, targetCount))
    : LEGACY_BATCH_SIZING.maxDeliveredPerBatch;
  return {
    schemaVersion: PICKS_SCHEMA_VERSION,
    generationId: data.generationId,
    generatedAtMs,
    refreshAtMs: finiteOr(data.refreshAtMs, nextLogicalDayStartMs(generatedAtMs)),
    lastScanAtMs: finiteOr(data.lastScanAtMs, generatedAtMs),
    deliveredCount: finiteOr(data.deliveredCount, picks.length),
    targetCount,
    maxDeliveredCount,
    picks,
    cooldowns,
    candidateUids: candidateUidsOf(picks, cooldowns),
  };
}

function candidateUidsOf(picks: StoredPick[], cooldowns: Record<string, number>): string[] {
  return [...new Set([...picks.map((p) => p.candidateUid), ...Object.keys(cooldowns)])].sort();
}

function withIndex(batch: PicksBatch): PicksBatch {
  return {...batch, candidateUids: candidateUidsOf(batch.picks, batch.cooldowns)};
}

const DAY_MS = 86_400_000;

/** The logical day `nowMs` falls in, as YYYY-MM-DD at the Picks day offset. */
export function logicalDayKey(nowMs: number): string {
  const shifted = nowMs + PICKS_CONFIG.logicalDayUtcOffsetMinutes * 60_000;
  return new Date(shifted).toISOString().slice(0, 10);
}

/** When the logical day containing `nowMs` ends: the next batch's earliest start. */
export function nextLogicalDayStartMs(nowMs: number): number {
  const offsetMs = PICKS_CONFIG.logicalDayUtcOffsetMinutes * 60_000;
  const shifted = nowMs + offsetMs;
  return Math.floor(shifted / DAY_MS) * DAY_MS + DAY_MS - offsetMs;
}

export function isBatchLive(batch: PicksBatch | null, nowMs: number): boolean {
  return batch !== null && nowMs < batch.refreshAtMs;
}

export function activePicks(batch: PicksBatch): StoredPick[] {
  return batch.picks.filter((pick) => pick.state === "active").sort((a, b) => a.rank - b.rank);
}

/** Cooldowns still running at `nowMs`. */
export function liveCooldowns(cooldowns: Record<string, number>, nowMs: number): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [uid, until] of Object.entries(cooldowns)) {
    if (until > nowMs) out[uid] = until;
  }
  return out;
}

/**
 * Cooldowns carried into the next batch: the running ones, plus every Pick
 * that is expiring undecided. Decided Picks need no cooldown — the canonical
 * like/pass/match state already keeps them out of the pool for good.
 */
export function cooldownsAfterExpiry(batch: PicksBatch | null, nowMs: number): Record<string, number> {
  if (!batch) return {};
  const next = liveCooldowns(batch.cooldowns, nowMs);
  for (const pick of batch.picks) {
    if (pick.state === "active") {
      next[pick.candidateUid] = Math.max(
        next[pick.candidateUid] ?? 0,
        nowMs + PICKS_CONFIG.expiredCooldownMs,
      );
    }
  }
  return next;
}

/** Everyone a generation or top-up must not pick. */
export function excludedFromSelection(batch: PicksBatch | null, nowMs: number): Set<string> {
  if (!batch) return new Set();
  return new Set([
    ...batch.picks.map((pick) => pick.candidateUid),
    ...Object.keys(liveCooldowns(batch.cooldowns, nowMs)),
  ]);
}

export function buildStoredPicks(
  generationId: string,
  composed: ComposedPick[],
  cards: Map<string, PickCardSnapshot>,
  nowMs: number,
): StoredPick[] {
  return composed.map((pick) => ({
    candidateUid: pick.candidateUid,
    pickId: pickIdFor(generationId, pick.candidateUid),
    rank: pick.rank,
    pickType: pick.pickType,
    labels: pick.labels,
    reasons: pick.reasons,
    overallScore: pick.overallScore,
    isBoosted: pick.isBoosted,
    selectionStrategy: pick.selectionStrategy,
    state: "active" as const,
    deliveredAtMs: nowMs,
    decidedAtMs: null,
    card: cards.get(pick.candidateUid) as PickCardSnapshot,
  }));
}

export function newBatch(input: {
  generationId: string;
  nowMs: number;
  picks: StoredPick[];
  cooldowns: Record<string, number>;
  sizing?: PicksSizing;
}): PicksBatch {
  const sizing = input.sizing ?? PICKS_SIZING;
  return withIndex({
    schemaVersion: PICKS_SCHEMA_VERSION,
    generationId: input.generationId,
    generatedAtMs: input.nowMs,
    refreshAtMs: nextLogicalDayStartMs(input.nowMs),
    lastScanAtMs: input.nowMs,
    deliveredCount: input.picks.length,
    targetCount: sizing.targetCount,
    maxDeliveredCount: sizing.maxDeliveredPerBatch,
    picks: input.picks,
    cooldowns: input.cooldowns,
    candidateUids: [],
  });
}

/** Adds replacement Picks to a live batch. */
export function appendPicks(batch: PicksBatch, picks: StoredPick[], nowMs: number): PicksBatch {
  return withIndex({
    ...batch,
    picks: [...batch.picks, ...picks],
    deliveredCount: batch.deliveredCount + picks.length,
    lastScanAtMs: nowMs,
  });
}

/** Records a top-up scan that found nobody, so the next one waits its turn. */
export function markScanned(batch: PicksBatch, nowMs: number): PicksBatch {
  return {...batch, lastScanAtMs: nowMs};
}

/**
 * Picks that used up a slot of today's set: everything except the ones that
 * stopped being eligible. A like, a pass or a match spends the slot for good,
 * so deciding quickly never buys more people.
 */
export function slotsUsed(batch: PicksBatch): number {
  return batch.picks.filter((pick) => pick.state !== "ineligible").length;
}

/**
 * Whether a live batch may look for more people now: it has open slots (a
 * short first batch, or a Pick that stopped being eligible), delivery budget
 * left, and has not scanned recently.
 */
export function needsTopUp(batch: PicksBatch, nowMs: number): boolean {
  return (
    slotsUsed(batch) < batch.targetCount &&
    batch.deliveredCount < batch.maxDeliveredCount &&
    nowMs - batch.lastScanAtMs >= PICKS_CONFIG.topUpMinIntervalMs
  );
}

/** How many replacements a top-up may add. */
export function topUpSlots(batch: PicksBatch): number {
  const byTarget = batch.targetCount - slotsUsed(batch);
  const byBudget = batch.maxDeliveredCount - batch.deliveredCount;
  return Math.max(0, Math.min(byTarget, byBudget));
}

/**
 * Moves one Pick out of `active`. Idempotent: deciding an already-decided Pick
 * changes nothing, except that a like later confirmed as a match is upgraded.
 */
export function applyDecision(
  batch: PicksBatch,
  candidateUid: string,
  decision: PickDecision,
  nowMs: number,
): {batch: PicksBatch; changed: boolean; pick: StoredPick | null} {
  let changed = false;
  let found: StoredPick | null = null;
  const picks = batch.picks.map((pick) => {
    if (pick.candidateUid !== candidateUid) return pick;
    const upgradeToMatch = decision === "matched" && pick.state === "liked";
    if (pick.state !== "active" && !upgradeToMatch) {
      found = pick;
      return pick;
    }
    changed = true;
    found = {
      ...pick,
      state: decision,
      decidedAtMs: pick.decidedAtMs ?? nowMs,
    };
    return found;
  });
  return {batch: changed ? {...batch, picks} : batch, changed, pick: found};
}

/**
 * Applies what the server learned while revalidating: active Picks that are
 * now liked, passed, matched or no longer eligible leave the active set.
 */
export function applyRevalidation(
  batch: PicksBatch,
  outcomes: Map<string, PickState>,
  nowMs: number,
): {batch: PicksBatch; changed: boolean} {
  let changed = false;
  const picks = batch.picks.map((pick) => {
    const outcome = outcomes.get(pick.candidateUid);
    if (pick.state !== "active" || !outcome || outcome === "active") return pick;
    changed = true;
    return {...pick, state: outcome, decidedAtMs: nowMs};
  });
  return {batch: changed ? {...batch, picks} : batch, changed};
}

/**
 * Removes every trace of one candidate from a batch — for account deletion.
 * Returns null when the batch never mentioned them.
 */
export function scrubCandidate(batch: PicksBatch, candidateUid: string): PicksBatch | null {
  const mentioned =
    batch.picks.some((pick) => pick.candidateUid === candidateUid) ||
    candidateUid in batch.cooldowns;
  if (!mentioned) return null;
  const cooldowns = {...batch.cooldowns};
  delete cooldowns[candidateUid];
  return withIndex({
    ...batch,
    picks: batch.picks.filter((pick) => pick.candidateUid !== candidateUid),
    cooldowns,
  });
}
