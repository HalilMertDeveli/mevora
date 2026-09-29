import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {isPickType} from "./categories.js";
import type {PickType} from "./types.js";

/**
 * The Mevora Picks introduction funnel, measured on the server.
 *
 *   delivered → liked → mutual match → conversation started → survived 24h
 *
 * Every step here is something the server itself observed: a batch it wrote,
 * a decision it recorded, a match it created, a message it relayed. The app
 * reports impressions and profile opens to product analytics separately;
 * those are the only steps only the device can see.
 *
 * Counters live in `pickFunnelDaily/{YYYY-MM-DD}` (UTC), with a total and a
 * per-Pick-type count for each step, and no user ids at all. Successful
 * Introduction Rate is then, for any window,
 *
 *   sum(conversationSurvived24h) / sum(delivered)
 *
 * (or conversationStarted / delivered for the looser definition). This module
 * records the inputs; it does not publish a rate.
 */

export type FunnelStep =
  | "delivered"
  | "liked"
  | "passed"
  | "mutualMatch"
  | "conversationStarted"
  | "conversationSurvived24h";

/** Conversation "survives" once it is still going this long after it started. */
export const CONVERSATION_SURVIVAL_MS = 24 * 60 * 60 * 1000;

export function funnelDayId(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

/**
 * Increments funnel counters. Never throws: a measurement failure must not
 * fail the like, pass or message it is measuring.
 */
export async function bumpFunnel(
  db: Firestore,
  step: FunnelStep,
  pickTypes: PickType[],
  nowMs = Date.now(),
): Promise<void> {
  if (pickTypes.length === 0) return;
  const updates: Record<string, unknown> = {
    day: funnelDayId(nowMs),
    [step]: FieldValue.increment(pickTypes.length),
    updatedAt: FieldValue.serverTimestamp(),
  };
  const byType = new Map<PickType, number>();
  for (const type of pickTypes) byType.set(type, (byType.get(type) ?? 0) + 1);
  for (const [type, count] of byType) {
    updates[`${step}_${type}`] = FieldValue.increment(count);
  }
  try {
    await db.doc(`pickFunnelDaily/${funnelDayId(nowMs)}`).set(updates, {merge: true});
    logger.info("pick_funnel", {step, count: pickTypes.length, pickTypes: [...byType.keys()]});
  } catch (error) {
    logger.warn("pick_funnel_write_failed", {
      step,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

/**
 * Pick attribution stored on a match: which side met the other through Picks,
 * and as what kind of Pick. Keyed by the viewer who was shown the Pick.
 */
export type PickIntroduction = {pickType: PickType; generationId: string};

export function introductionsOf(match: DocumentData | undefined): Map<string, PickIntroduction> {
  const out = new Map<string, PickIntroduction>();
  const raw = match?.introducedByPick;
  if (!raw || typeof raw !== "object") return out;
  for (const [uid, value] of Object.entries(raw as Record<string, unknown>)) {
    const entry = value as Record<string, unknown> | null;
    if (entry && isPickType(entry.pickType) && typeof entry.generationId === "string") {
      out.set(uid, {pickType: entry.pickType, generationId: entry.generationId});
    }
  }
  return out;
}

function toMillis(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value && typeof value === "object") {
    const record = value as {toMillis?: () => number};
    if (typeof record.toMillis === "function") return record.toMillis();
  }
  return null;
}

/**
 * The conversation milestones a new message reaches on a Pick-introduced
 * match. Pure: the caller writes `updates` inside its message transaction and
 * bumps the funnel after it commits.
 *
 * Started = both people have written. Survived = a message arrives at least
 * 24 hours after the conversation started. Each is recorded once.
 */
export function pickConversationMilestones(input: {
  match: DocumentData | undefined;
  messagedUserIds: string[];
  nowMs: number;
}): {updates: Record<string, number>; step: FunnelStep | null; pickTypes: PickType[]} {
  const none = {updates: {}, step: null, pickTypes: []};
  const introductions = introductionsOf(input.match);
  if (introductions.size === 0) return none;
  const pickTypes = [...new Set([...introductions.values()].map((entry) => entry.pickType))];
  const userIds = ((input.match?.userIds as string[] | undefined) ?? []).filter(Boolean);
  const messaged = new Set(input.messagedUserIds);
  const startedAt = toMillis(input.match?.pickConversationStartedAt);
  if (startedAt === null) {
    const bothWrote = userIds.length === 2 && userIds.every((uid) => messaged.has(uid));
    return bothWrote
      ? {updates: {pickConversationStartedAt: input.nowMs}, step: "conversationStarted", pickTypes}
      : none;
  }
  if (
    toMillis(input.match?.pickConversationSurvived24hAt) === null &&
    input.nowMs - startedAt >= CONVERSATION_SURVIVAL_MS
  ) {
    return {
      updates: {pickConversationSurvived24hAt: input.nowMs},
      step: "conversationSurvived24h",
      pickTypes,
    };
  }
  return none;
}
