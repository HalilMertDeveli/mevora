/**
 * Humor Core progression — pure rules, no Firestore.
 *
 * Which Core entries a member rates today is decided here and nowhere else,
 * from two inputs: the member's own stored state and the server's logical day.
 * The same design as the Relationship Core questions
 * (`relationshipLearning/schedule.ts`), for the same reasons:
 *
 * - There is no position counter and no calendar index. Today's set is "the
 *   first open entries in canonical order", so a member who was away for a
 *   week comes back to the entries they left, not to a later range.
 * - The first response of a day freezes that day's ids on the member's state.
 *   Rating V16 therefore cannot pull V21 into today, finishing the initial
 *   fifteen cannot unlock the daily five on the same day, and a restart or a
 *   second device sees the same set.
 * - An entry is *resolved* when it is rated, or waived for this member (media
 *   that never played, or an item they reported). Only a rating is evidence;
 *   a waiver stores no rating and is never compared with anyone's answer.
 *
 * The sequence is a parameter rather than an import so that a later source of
 * entries (a curator-managed tail) can be passed in without touching the
 * scheduling rules.
 */
import {createHash} from "node:crypto";
import {HUMOR_CORE, type HumorCoreEntry} from "./coreSequence.js";
import {HUMOR_RATINGS, type HumorRating} from "./types.js";

export const HUMOR_CORE_STATE_SCHEMA = 1;

/**
 * Media that would not play is deferred, not skipped: the entry comes back on
 * the member's next day. After this many distinct days of failing for the same
 * member it is waived for them, so a clip that is dead on their device cannot
 * hold their progress forever.
 */
export const HUMOR_CORE_MEDIA_WAIVE_AFTER_DAYS = 2;

export type HumorCoreKind = "onboarding" | "core";

export type HumorCoreAnswer = {
  rating: HumorRating;
  /** The logical day it was rated on; null for a rating carried over from before Core. */
  dayId: string | null;
  answeredAtMs: number;
  source: "core" | "legacy";
};

export type HumorCoreWaiver = {
  reason: "media_failed" | "reported";
  dayId: string | null;
  atMs: number;
};

export type HumorCoreMediaFailure = {
  /** Distinct logical days the media failed on, oldest first. */
  days: string[];
  lastAtMs: number;
};

export type HumorCoreToday = {
  dayId: string | null;
  setId: string | null;
  /** The frozen ids of the day; null until the day is touched. */
  contentIds: string[] | null;
  kind: HumorCoreKind | null;
  completedAtMs: number | null;
};

export type HumorCoreMigration = {
  from: "none" | "adaptive-v1";
  legacyComplete: boolean;
  legacyCompletedCount: number;
  importedRatings: number;
  importedWaivers: number;
  atMs: number;
};

/** `users/{uid}/humor/core`. */
export type HumorCoreState = {
  schemaVersion: number;
  answers: Record<string, HumorCoreAnswer>;
  waived: Record<string, HumorCoreWaiver>;
  mediaFailures: Record<string, HumorCoreMediaFailure>;
  /** When the initial calibration was finished; null while it is running. */
  initialCompletedAtMs: number | null;
  today: HumorCoreToday;
  completedDays: number;
  migration: HumorCoreMigration | null;
};

export type HumorCoreSet = {
  kind: HumorCoreKind;
  dayId: string;
  setId: string;
  contentIds: string[];
};

export type HumorCoreItemStatus = "rated" | "waived" | "deferred" | "open";

const NONE: ReadonlySet<string> = new Set();
const DAY_ID = /^\d{4}-\d{2}-\d{2}$/;

function isRating(value: unknown): value is HumorRating {
  return typeof value === "string" && (HUMOR_RATINGS as readonly string[]).includes(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function finiteOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function dayOrNull(value: unknown): string | null {
  return typeof value === "string" && DAY_ID.test(value) ? value : null;
}

export function defaultHumorCoreState(): HumorCoreState {
  return {
    schemaVersion: HUMOR_CORE_STATE_SCHEMA,
    answers: {},
    waived: {},
    mediaFailures: {},
    initialCompletedAtMs: null,
    today: {dayId: null, setId: null, contentIds: null, kind: null, completedAtMs: null},
    completedDays: 0,
    migration: null,
  };
}

/**
 * Normalize a stored state. Entries for ids that are not in [sequence] are
 * dropped, as is anything malformed, so a hand-edited or older document can
 * never put a member on content the sequence does not contain.
 */
export function parseHumorCoreState(
  data: Record<string, unknown> | undefined,
  sequence: readonly HumorCoreEntry[],
): HumorCoreState {
  const state = defaultHumorCoreState();
  if (!data) {
    return state;
  }
  const known = new Set(sequence.map((entry) => entry.id));

  if (isRecord(data.answers)) {
    for (const [id, raw] of Object.entries(data.answers)) {
      if (!known.has(id) || !isRecord(raw) || !isRating(raw.rating)) continue;
      state.answers[id] = {
        rating: raw.rating,
        dayId: dayOrNull(raw.dayId),
        answeredAtMs: finiteOrNull(raw.answeredAtMs) ?? 0,
        source: raw.source === "legacy" ? "legacy" : "core",
      };
    }
  }
  if (isRecord(data.waived)) {
    for (const [id, raw] of Object.entries(data.waived)) {
      if (!known.has(id) || !isRecord(raw)) continue;
      state.waived[id] = {
        reason: raw.reason === "reported" ? "reported" : "media_failed",
        dayId: dayOrNull(raw.dayId),
        atMs: finiteOrNull(raw.atMs) ?? 0,
      };
    }
  }
  if (isRecord(data.mediaFailures)) {
    for (const [id, raw] of Object.entries(data.mediaFailures)) {
      if (!known.has(id) || !isRecord(raw) || !Array.isArray(raw.days)) continue;
      const days = [...new Set(raw.days.map(dayOrNull).filter((d): d is string => d !== null))];
      if (days.length === 0) continue;
      state.mediaFailures[id] = {days, lastAtMs: finiteOrNull(raw.lastAtMs) ?? 0};
    }
  }
  state.initialCompletedAtMs = finiteOrNull(data.initialCompletedAtMs);

  if (isRecord(data.today)) {
    const today = data.today;
    const dayId = dayOrNull(today.dayId);
    if (dayId) {
      state.today = {
        dayId,
        setId: typeof today.setId === "string" ? today.setId : null,
        contentIds: Array.isArray(today.contentIds)
          ? today.contentIds.filter((id): id is string => typeof id === "string" && known.has(id))
          : null,
        kind: today.kind === "onboarding" || today.kind === "core" ? today.kind : null,
        completedAtMs: finiteOrNull(today.completedAtMs),
      };
    }
  }
  state.completedDays = Math.max(0, Math.floor(finiteOrNull(data.completedDays) ?? 0));

  if (isRecord(data.migration)) {
    const m = data.migration;
    state.migration = {
      from: m.from === "adaptive-v1" ? "adaptive-v1" : "none",
      legacyComplete: m.legacyComplete === true,
      legacyCompletedCount: Math.max(0, Math.floor(finiteOrNull(m.legacyCompletedCount) ?? 0)),
      importedRatings: Math.max(0, Math.floor(finiteOrNull(m.importedRatings) ?? 0)),
      importedWaivers: Math.max(0, Math.floor(finiteOrNull(m.importedWaivers) ?? 0)),
      atMs: finiteOrNull(m.atMs) ?? 0,
    };
  }
  return state;
}

// ---------------------------------------------------------------------------
// Sequence views
// ---------------------------------------------------------------------------

/**
 * Entries that can still be handed out: active in the sequence and not in
 * [unavailable] — the ids whose content document cannot be served right now
 * (taken down, deactivated, missing). An unavailable entry is treated exactly
 * like a retired one: skipped, never substituted.
 */
function liveEntries(
  sequence: readonly HumorCoreEntry[],
  unavailable: ReadonlySet<string>,
): HumorCoreEntry[] {
  return sequence.filter((entry) => entry.active && !unavailable.has(entry.id));
}

/** The live part of V1 … V15. Retiring one shrinks it; nothing is backfilled. */
function onboardingEntries(
  sequence: readonly HumorCoreEntry[],
  unavailable: ReadonlySet<string>,
): HumorCoreEntry[] {
  return liveEntries(sequence.slice(0, HUMOR_CORE.onboardingCount), unavailable);
}

export function isCoreResolved(state: HumorCoreState, id: string): boolean {
  return state.answers[id] !== undefined || state.waived[id] !== undefined;
}

/** The initial calibration is behind this member. */
export function hasFinishedCoreOnboarding(
  state: HumorCoreState,
  sequence: readonly HumorCoreEntry[],
  unavailable: ReadonlySet<string> = NONE,
): boolean {
  if (state.initialCompletedAtMs !== null) {
    return true;
  }
  // Nothing servable is an empty catalogue, not a finished calibration.
  const entries = onboardingEntries(sequence, unavailable);
  return entries.length > 0 && entries.every((entry) => isCoreResolved(state, entry.id));
}

/** Initial-calibration progress as the member sees it ("7 / 15"). */
export function coreOnboardingProgress(
  state: HumorCoreState,
  sequence: readonly HumorCoreEntry[],
  unavailable: ReadonlySet<string> = NONE,
): {completedCount: number; totalCount: number; complete: boolean} {
  const entries = onboardingEntries(sequence, unavailable);
  const complete = hasFinishedCoreOnboarding(state, sequence, unavailable);
  const resolved = entries.filter((entry) => isCoreResolved(state, entry.id)).length;
  return {
    completedCount: complete ? entries.length : resolved,
    totalCount: entries.length,
    complete,
  };
}

/** Nothing is left to hand out: every live entry is resolved. */
export function isCoreSequenceExhausted(
  state: HumorCoreState,
  sequence: readonly HumorCoreEntry[],
  unavailable: ReadonlySet<string> = NONE,
): boolean {
  return liveEntries(sequence, unavailable).every((entry) => isCoreResolved(state, entry.id));
}

// ---------------------------------------------------------------------------
// Today's set
// ---------------------------------------------------------------------------

function setIdOf(kind: HumorCoreKind, dayId: string, ids: readonly string[]): string {
  if (ids.length === 0) {
    return `${kind}-${dayId}-none`;
  }
  const digest = createHash("sha1").update(ids.join(",")).digest("hex").slice(0, 10);
  return `${kind}-${dayId}-${digest}`;
}

function buildSet(kind: HumorCoreKind, dayId: string, ids: readonly string[]): HumorCoreSet {
  return {kind, dayId, setId: setIdOf(kind, dayId, ids), contentIds: [...ids]};
}

/**
 * The Core entries [state]'s member has on [dayId].
 *
 * - A day already touched keeps the ids frozen on it, minus any that have
 *   since been retired or taken down.
 * - Otherwise, while the initial calibration is open: what is left of V1–V15.
 * - Otherwise: the first `dailyCount` open entries in canonical order.
 */
export function memberCoreSet(
  state: HumorCoreState,
  dayId: string,
  sequence: readonly HumorCoreEntry[],
  unavailable: ReadonlySet<string> = NONE,
): HumorCoreSet {
  const live = liveEntries(sequence, unavailable);
  const touchedToday = state.today.dayId === dayId;
  if (touchedToday && state.today.contentIds) {
    const liveIds = new Set(live.map((entry) => entry.id));
    return buildSet(
      state.today.kind ?? "core",
      dayId,
      state.today.contentIds.filter((id) => liveIds.has(id)),
    );
  }
  if (touchedToday && state.today.completedAtMs !== null) {
    return buildSet(state.today.kind ?? "core", dayId, []);
  }
  if (!hasFinishedCoreOnboarding(state, sequence, unavailable)) {
    return buildSet(
      "onboarding",
      dayId,
      onboardingEntries(sequence, unavailable)
        .filter((entry) => !isCoreResolved(state, entry.id))
        .map((entry) => entry.id),
    );
  }
  return buildSet(
    "core",
    dayId,
    live
      .filter((entry) => !isCoreResolved(state, entry.id))
      .slice(0, HUMOR_CORE.dailyCount)
      .map((entry) => entry.id),
  );
}

export function coreItemStatus(
  state: HumorCoreState,
  id: string,
  dayId: string,
): HumorCoreItemStatus {
  if (state.answers[id]) return "rated";
  if (state.waived[id]) return "waived";
  if (state.mediaFailures[id]?.days.includes(dayId)) return "deferred";
  return "open";
}

export type HumorCoreSetProgress = {
  total: number;
  /** Items the member is done with today: rated, waived or deferred. */
  answeredCount: number;
  completed: boolean;
  /** Index of the first open item, or `total` when none is open. */
  nextIndex: number;
  statuses: HumorCoreItemStatus[];
};

export function coreSetProgress(state: HumorCoreState, set: HumorCoreSet): HumorCoreSetProgress {
  const statuses = set.contentIds.map((id) => coreItemStatus(state, id, set.dayId));
  const firstOpen = statuses.indexOf("open");
  const total = statuses.length;
  return {
    total,
    answeredCount: statuses.filter((status) => status !== "open").length,
    completed:
      total > 0
        ? firstOpen < 0
        : state.today.dayId === set.dayId && state.today.completedAtMs !== null,
    nextIndex: firstOpen < 0 ? total : firstOpen,
    statuses,
  };
}

// ---------------------------------------------------------------------------
// Responses
// ---------------------------------------------------------------------------

export type HumorCoreApplyResult =
  | {
      ok: true;
      state: HumorCoreState;
      changed: boolean;
      completedTodayNow: boolean;
      onboardingCompletedNow: boolean;
    }
  | {ok: false; reason: "not-in-set"};

/** Freeze [set] as today's set, keeping an earlier freeze of the same day. */
function frozenToday(state: HumorCoreState, set: HumorCoreSet): HumorCoreToday {
  const touchedToday = state.today.dayId === set.dayId;
  const alreadyFrozen = touchedToday && state.today.contentIds !== null;
  return {
    dayId: set.dayId,
    setId: alreadyFrozen && state.today.setId ? state.today.setId : set.setId,
    contentIds: alreadyFrozen ? (state.today.contentIds as string[]) : [...set.contentIds],
    kind: set.kind,
    completedAtMs: touchedToday ? state.today.completedAtMs : null,
  };
}

/** Stamp day completion and the end of the initial calibration, each once. */
function settle(input: {
  before: HumorCoreState;
  after: HumorCoreState;
  set: HumorCoreSet;
  nowMs: number;
  sequence: readonly HumorCoreEntry[];
  unavailable: ReadonlySet<string>;
}): HumorCoreApplyResult {
  const {before, set, nowMs, sequence, unavailable} = input;
  let state = input.after;
  const progress = coreSetProgress(state, set);
  const completedTodayNow = progress.completed && state.today.completedAtMs === null;
  if (completedTodayNow) {
    state = {
      ...state,
      today: {...state.today, completedAtMs: nowMs},
      completedDays: state.completedDays + 1,
    };
  }
  const finishedBefore = hasFinishedCoreOnboarding(before, sequence, unavailable);
  const finishedNow = hasFinishedCoreOnboarding(state, sequence, unavailable);
  if (finishedNow && state.initialCompletedAtMs === null) {
    state = {...state, initialCompletedAtMs: nowMs};
  }
  return {
    ok: true,
    state,
    changed: true,
    completedTodayNow,
    onboardingCompletedNow: !finishedBefore && finishedNow,
  };
}

const unchanged = (state: HumorCoreState): HumorCoreApplyResult => ({
  ok: true,
  state,
  changed: false,
  completedTodayNow: false,
  onboardingCompletedNow: false,
});

/**
 * A rating for [id]. Accepted only for an entry in today's [set]; the same
 * rating again changes nothing, a different one replaces it.
 */
export function applyCoreRating(input: {
  state: HumorCoreState;
  set: HumorCoreSet;
  id: string;
  rating: HumorRating;
  nowMs: number;
  sequence: readonly HumorCoreEntry[];
  unavailable?: ReadonlySet<string>;
}): HumorCoreApplyResult {
  const {state, set, id, rating, nowMs} = input;
  if (!set.contentIds.includes(id)) {
    return {ok: false, reason: "not-in-set"};
  }
  const existing = state.answers[id];
  if (existing?.rating === rating) {
    return unchanged(state);
  }
  const waived = {...state.waived};
  delete waived[id];
  const after: HumorCoreState = {
    ...state,
    answers: {
      ...state.answers,
      [id]: {
        rating,
        dayId: set.dayId,
        answeredAtMs: existing?.answeredAtMs ?? nowMs,
        source: "core",
      },
    },
    waived,
    today: frozenToday(state, set),
  };
  return settle({
    before: state,
    after,
    set,
    nowMs,
    sequence: input.sequence,
    unavailable: input.unavailable ?? NONE,
  });
}

/**
 * The media of [id] would not play. Never evidence: no rating is stored. The
 * entry is done for today and comes back on the member's next day; once it
 * has failed on `HUMOR_CORE_MEDIA_WAIVE_AFTER_DAYS` distinct days it is waived
 * for this member. A recorded rating is never overridden.
 */
export function applyCoreMediaFailure(input: {
  state: HumorCoreState;
  set: HumorCoreSet;
  id: string;
  nowMs: number;
  sequence: readonly HumorCoreEntry[];
  unavailable?: ReadonlySet<string>;
}): HumorCoreApplyResult {
  const {state, set, id, nowMs} = input;
  if (!set.contentIds.includes(id)) {
    return {ok: false, reason: "not-in-set"};
  }
  if (isCoreResolved(state, id)) {
    return unchanged(state);
  }
  const days = state.mediaFailures[id]?.days ?? [];
  if (days.includes(set.dayId)) {
    return unchanged(state);
  }
  const failedDays = [...days, set.dayId];
  const waive = failedDays.length >= HUMOR_CORE_MEDIA_WAIVE_AFTER_DAYS;
  const after: HumorCoreState = {
    ...state,
    mediaFailures: {...state.mediaFailures, [id]: {days: failedDays, lastAtMs: nowMs}},
    waived: waive
      ? {...state.waived, [id]: {reason: "media_failed", dayId: set.dayId, atMs: nowMs}}
      : state.waived,
    today: frozenToday(state, set),
  };
  return settle({
    before: state,
    after,
    set,
    nowMs,
    sequence: input.sequence,
    unavailable: input.unavailable ?? NONE,
  });
}

/**
 * The member reported [id]. It is waived for them — never shown again, never
 * compared — unless they had already rated it, in which case the rating stands.
 * An entry outside today's set is left alone: it is not in front of them.
 */
export function applyCoreReport(input: {
  state: HumorCoreState;
  set: HumorCoreSet;
  id: string;
  nowMs: number;
  sequence: readonly HumorCoreEntry[];
  unavailable?: ReadonlySet<string>;
}): HumorCoreApplyResult {
  const {state, set, id, nowMs} = input;
  if (!set.contentIds.includes(id) || isCoreResolved(state, id)) {
    return unchanged(state);
  }
  const after: HumorCoreState = {
    ...state,
    waived: {...state.waived, [id]: {reason: "reported", dayId: set.dayId, atMs: nowMs}},
    today: frozenToday(state, set),
  };
  return settle({
    before: state,
    after,
    set,
    nowMs,
    sequence: input.sequence,
    unavailable: input.unavailable ?? NONE,
  });
}

// ---------------------------------------------------------------------------
// Members from before the Core sequence
// ---------------------------------------------------------------------------

/**
 * The first Core state of a member, built once from what they did before the
 * Core sequence existed. Nothing of theirs is rewritten or deleted — the
 * lifetime profile, the interaction documents and the old daily days stay as
 * they are; this only records where they stand in the canonical order.
 *
 * - A real rating of a Core entry counts as that entry answered (`legacy`), so
 *   it is not asked again. An entry they reported is waived for them. A plain
 *   skip marker resolves nothing: the entry is still asked.
 * - A member whose old calibration was finished is past the initial
 *   calibration here too. They are not asked to redo fifteen in one sitting:
 *   they take the open entries five a day, starting at V1.
 * - A member in the middle of the old calibration continues with whatever is
 *   left of V1–V15.
 * - If they finished the old calibration today, or already did the old daily
 *   set today, today is spent: Core starts tomorrow.
 */
export function migrateLegacyHumorCoreState(input: {
  sequence: readonly HumorCoreEntry[];
  /** Interaction documents for sequence ids, by id. */
  interactions: ReadonlyMap<string, {rating?: unknown; reported?: unknown}>;
  legacyReady: boolean;
  legacyCompletedCount: number;
  legacyCompletedAtMs: number | null;
  legacyDailyTouchedToday: boolean;
  todayId: string;
  dayIdOf: (ms: number) => string;
  nowMs: number;
}): HumorCoreState {
  const state = defaultHumorCoreState();
  let importedRatings = 0;
  let importedWaivers = 0;
  for (const entry of input.sequence) {
    const interaction = input.interactions.get(entry.id);
    if (!interaction) continue;
    if (isRating(interaction.rating)) {
      state.answers[entry.id] = {
        rating: interaction.rating,
        dayId: null,
        answeredAtMs: 0,
        source: "legacy",
      };
      importedRatings += 1;
    } else if (interaction.reported === true) {
      state.waived[entry.id] = {reason: "reported", dayId: null, atMs: 0};
      importedWaivers += 1;
    }
  }

  if (input.legacyReady) {
    state.initialCompletedAtMs = input.legacyCompletedAtMs ?? input.nowMs;
    const finishedToday =
      input.legacyCompletedAtMs !== null &&
      input.dayIdOf(input.legacyCompletedAtMs) >= input.todayId;
    if (finishedToday || input.legacyDailyTouchedToday) {
      state.today = {
        dayId: input.todayId,
        setId: null,
        contentIds: [],
        kind: finishedToday ? "onboarding" : "core",
        completedAtMs: input.legacyCompletedAtMs ?? input.nowMs,
      };
    }
  }

  const hadHistory =
    input.legacyReady || input.legacyCompletedCount > 0 || importedRatings + importedWaivers > 0;
  state.migration = {
    from: hadHistory ? "adaptive-v1" : "none",
    legacyComplete: input.legacyReady,
    legacyCompletedCount: Math.max(0, Math.floor(input.legacyCompletedCount)),
    importedRatings,
    importedWaivers,
    atMs: input.nowMs,
  };
  return state;
}

// ---------------------------------------------------------------------------
// Shared-content comparison
// ---------------------------------------------------------------------------

/**
 * contentId → rating for everything [state]'s member rated in the canonical
 * sequence. Because every member rates the same entries, two of these maps can
 * be compared entry by entry (`dailyResponseAgreement`). Waived and unrated
 * entries are absent on purpose: a missing rating is not a neutral answer.
 */
export function coreRatedAnswers(state: HumorCoreState): Map<string, HumorRating> {
  return new Map(Object.entries(state.answers).map(([id, answer]) => [id, answer.rating]));
}
