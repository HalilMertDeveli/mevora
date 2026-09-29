import {createHash} from "node:crypto";
import {PERSONALIZATION_ALGORITHM_VERSION, WEAK_SIGNALS, type StrongSignalType} from "./config.js";

/**
 * Deterministic signal definitions from interaction METADATA only.
 *
 * Nothing in this file (or anywhere in personalization) reads message text,
 * ciphertext or any other content: a conversation is described only by who
 * wrote, and when. The inputs below are the entire surface.
 */

const DAY_MS = 86_400_000;

/** Stored on the match document under `personalizationSignals`. Server-written only. */
export interface ConversationSignalState {
  /** When both people had written at least once. */
  startedAtMs: number | null;
  /** When mutual activity was seen at least 24h after the start. */
  survivedAtMs: number | null;
  /** When mutual activity was seen on a second distinct day. */
  secondSessionAtMs: number | null;
  /** UTC day index of the current day's activity. */
  day: number | null;
  /** Who has written on `day`. */
  daySenders: string[];
  /** Distinct UTC days on which both people wrote. */
  mutualDays: number;
  /** The last day already counted in `mutualDays`. */
  countedDay: number | null;
  /** Who has written since the 24h mark (for "survived"). */
  lateSenders: string[];
}

export function emptyConversationState(): ConversationSignalState {
  return {
    startedAtMs: null,
    survivedAtMs: null,
    secondSessionAtMs: null,
    day: null,
    daySenders: [],
    mutualDays: 0,
    countedDay: null,
    lateSenders: [],
  };
}

function numberOrNull(value: unknown): number | null {
  const n = Number(value);
  return value !== null && value !== undefined && Number.isFinite(n) ? n : null;
}

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.map(String).filter(Boolean) : [];
}

export function parseConversationState(raw: unknown): ConversationSignalState {
  if (!raw || typeof raw !== "object") return emptyConversationState();
  const data = raw as Record<string, unknown>;
  return {
    startedAtMs: numberOrNull(data.startedAtMs),
    survivedAtMs: numberOrNull(data.survivedAtMs),
    secondSessionAtMs: numberOrNull(data.secondSessionAtMs),
    day: numberOrNull(data.day),
    daySenders: stringList(data.daySenders),
    mutualDays: Math.max(0, Math.floor(numberOrNull(data.mutualDays) ?? 0)),
    countedDay: numberOrNull(data.countedDay),
    lateSenders: stringList(data.lateSenders),
  };
}

export const CONVERSATION_SURVIVAL_MS = DAY_MS;

/**
 * Advance a match's conversation state by one message. Returns the new state
 * and the milestones this message reached for the first time. Replaying the
 * same message (a retried trigger) reaches nothing new: every milestone is
 * gated on its own timestamp being unset.
 */
export function advanceConversationState(input: {
  state: ConversationSignalState;
  userIds: string[];
  /** messagedUserIds after this message's sender has been added. */
  messagedUserIds: string[];
  senderId: string;
  nowMs: number;
}): {state: ConversationSignalState; reached: StrongSignalType[]} {
  const {userIds, senderId, nowMs} = input;
  const state: ConversationSignalState = {
    ...input.state,
    daySenders: [...input.state.daySenders],
    lateSenders: [...input.state.lateSenders],
  };
  const reached: StrongSignalType[] = [];
  if (userIds.length !== 2 || !userIds.includes(senderId)) {
    return {state, reached};
  }
  const bothIn = (list: string[]) => userIds.every((uid) => list.includes(uid));

  // Mutual days: a day counts once both people wrote on it.
  const today = Math.floor(nowMs / DAY_MS);
  const countDay = () => {
    if (state.countedDay !== today) {
      state.mutualDays += 1;
      state.countedDay = today;
    }
  };
  if (state.day !== today) {
    state.day = today;
    state.daySenders = [senderId];
  } else if (!state.daySenders.includes(senderId)) {
    state.daySenders.push(senderId);
  }
  if (bothIn(state.daySenders)) countDay();

  if (state.startedAtMs === null && bothIn(input.messagedUserIds)) {
    state.startedAtMs = nowMs;
    reached.push("conversationStarted");
    // The day the conversation starts is its first mutual day, even when the
    // two first messages fell either side of midnight.
    countDay();
  }

  if (state.startedAtMs !== null && state.survivedAtMs === null &&
      nowMs - state.startedAtMs >= CONVERSATION_SURVIVAL_MS) {
    if (!state.lateSenders.includes(senderId)) state.lateSenders.push(senderId);
    if (bothIn(state.lateSenders)) {
      state.survivedAtMs = nowMs;
      reached.push("conversationSurvived");
    }
  }

  if (state.startedAtMs !== null && state.secondSessionAtMs === null && state.mutualDays >= 2) {
    state.secondSessionAtMs = nowMs;
    reached.push("secondSession");
  }
  return {state, reached};
}

export function serializeConversationState(state: ConversationSignalState): Record<string, unknown> {
  return {
    startedAtMs: state.startedAtMs,
    survivedAtMs: state.survivedAtMs,
    secondSessionAtMs: state.secondSessionAtMs,
    day: state.day,
    daySenders: state.daySenders,
    mutualDays: state.mutualDays,
    countedDay: state.countedDay,
    lateSenders: state.lateSenders,
  };
}

// ---------------------------------------------------------------------------
// Weak profile engagement.
// ---------------------------------------------------------------------------

export interface ProfileEngagement {
  detailsOpened: boolean;
  photosViewed: number;
  spotifyOpened: boolean;
  whyThisPersonOpened: boolean;
  /** Foreground-only time on the profile, as measured by the client. */
  dwellMs: number;
}

export function parseProfileEngagement(raw: Record<string, unknown>): ProfileEngagement {
  const count = Number(raw.photosViewed);
  const dwell = Number(raw.dwellMs);
  return {
    detailsOpened: raw.detailsOpened === true,
    photosViewed: Number.isFinite(count) ? Math.max(0, Math.min(50, Math.floor(count))) : 0,
    spotifyOpened: raw.spotifyOpened === true,
    whyThisPersonOpened: raw.whyThisPersonOpened === true,
    dwellMs: Number.isFinite(dwell) ? Math.max(0, dwell) : 0,
  };
}

/**
 * Foreground dwell -> small strength. Clamped and bucketed, and anything past
 * the idle ceiling counts as nothing: a profile left open while the phone sat
 * on the table is not attraction.
 */
export function dwellStrength(dwellMs: number): number {
  const {bucketsMs, strengths, ignoreAboveMs} = WEAK_SIGNALS.dwell;
  if (!Number.isFinite(dwellMs) || dwellMs <= 0 || dwellMs > ignoreAboveMs) return 0;
  let bucket = 0;
  for (const edge of bucketsMs) {
    if (dwellMs >= edge) bucket += 1;
  }
  return strengths[bucket];
}

/** Total strength of one engagement event, capped far below a like. */
export function engagementStrength(engagement: ProfileEngagement): number {
  const total =
    (engagement.detailsOpened ? WEAK_SIGNALS.detailsOpened : 0) +
    (engagement.photosViewed >= 2 ? WEAK_SIGNALS.photosBrowsed : 0) +
    (engagement.spotifyOpened ? WEAK_SIGNALS.spotifyOpened : 0) +
    (engagement.whyThisPersonOpened ? WEAK_SIGNALS.whyThisPersonOpened : 0) +
    dwellStrength(engagement.dwellMs);
  return Math.min(WEAK_SIGNALS.maxTotal, Math.round(total * 1000) / 1000);
}

// ---------------------------------------------------------------------------
// Event identity.
// ---------------------------------------------------------------------------

/**
 * Deterministic ledger id for one learning event. The other person's uid is
 * hashed in, never stored, so the ledger holds no one else's identifier.
 */
export function personalizationEventId(input: {
  type: string;
  actorUid: string;
  otherUid: string;
  /** What makes this occurrence unique: a matchId, a UTC day, ... */
  key: string;
}): string {
  const digest = createHash("sha256")
    .update(
      `${PERSONALIZATION_ALGORITHM_VERSION}|${input.type}|${input.actorUid}|${input.otherUid}|${input.key}`,
    )
    .digest("hex")
    .slice(0, 32);
  return `${input.type}_${digest}`;
}

export function utcDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}
