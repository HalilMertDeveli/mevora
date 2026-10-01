import {
  ADJUSTMENT_BOUNDS,
  PERSONALIZATION_DIMENSIONS,
} from "../personalization/config.js";
import type {Adjustments} from "../personalization/learner.js";
import {isImportanceQuestion, learningQuestion} from "./catalog.js";
import {ANSWER_WRITE_LIMIT, DECLARED_IMPORTANCE, LEARNING_STATE_SCHEMA_VERSION} from "./config.js";
import {
  hasFinishedOnboarding,
  nextLearningDayStartMs,
  type DailySet,
  type DailySetKind,
} from "./schedule.js";

/**
 * A member's relationship-question state and the pure rules over it. Nothing
 * here reads Firestore, the wall clock or a random source: the same state,
 * daily set and clock always give the same result.
 *
 * Answers accumulate: every question keeps the member's latest answer, the
 * question version it was given for, and the logical day it was given on. A
 * question is asked once; an answer in the question's current version means
 * it is done, whatever day it was given on.
 */

export interface StoredAnswer {
  answerId: string;
  /** The question version the member actually saw. */
  version: number;
  /** The logical day this answer was given on. */
  dateKey: string;
  answeredAtMs: number;
}

export interface LearningState {
  exists: boolean;
  schemaVersion: number;
  /**
   * True for members who finished onboarding after relationship questions
   * shipped: their first Picks wait for the onboarding questions (Q1-Q15).
   */
  required: boolean;
  answers: Record<string, StoredAnswer>;
  /** When the member first completed a set — for a new member, onboarding. */
  initialCompletedAtMs: number | null;
  /**
   * The day the member last touched: its frozen set (ids and kind, written
   * with the first answer or skip of that day) and its progress markers.
   * `questionIds` is null on state written before the Core sequence.
   */
  daily: {
    dateKey: string | null;
    questionSetId: string | null;
    questionIds: string[] | null;
    kind: DailySetKind | null;
    completedAtMs: number | null;
    skippedAtMs: number | null;
  };
  /** Completed daily sets, ever. */
  completedDays: number;
  /** Daily answers given per calendar month (YYYY-MM), for "bu ay N soru". */
  answerCounts: Record<string, number>;
  /** New-member onboarding journey facts (see journeyStage). */
  journey: {
    /** "Skip for now" on the Humor Lab step; the lab stays open for later. */
    humorSkippedAtMs: number | null;
  };
  writeWindow: {startMs: number; count: number} | null;
}

export function emptyLearningState(): LearningState {
  return {
    exists: false,
    schemaVersion: LEARNING_STATE_SCHEMA_VERSION,
    required: false,
    answers: {},
    initialCompletedAtMs: null,
    daily: {
      dateKey: null,
      questionSetId: null,
      questionIds: null,
      kind: null,
      completedAtMs: null,
      skippedAtMs: null,
    },
    completedDays: 0,
    answerCounts: {},
    journey: {humorSkippedAtMs: null},
    writeWindow: null,
  };
}

function positiveMs(value: unknown): number | null {
  const n = Number(value);
  return value !== null && value !== undefined && Number.isFinite(n) && n > 0 ? n : null;
}

function dateKeyOrNull(value: unknown): string | null {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

/** A stored frozen set: known question ids only, each once. Null when none was stored. */
function questionIdsOrNull(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  return [...new Set(value.filter((id): id is string => learningQuestion(id) !== null))];
}

/**
 * Reads a stored state defensively. Unknown questions, foreign answer ids and
 * malformed entries are dropped rather than trusted — including answers to
 * questions from earlier catalogs, which simply no longer count.
 */
export function parseLearningState(raw: unknown): LearningState {
  const state = emptyLearningState();
  if (!raw || typeof raw !== "object") return state;
  const data = raw as Record<string, unknown>;
  state.exists = true;
  state.required = data.required === true;
  const answers = (data.answers ?? {}) as Record<string, unknown>;
  if (answers && typeof answers === "object") {
    for (const [questionId, value] of Object.entries(answers)) {
      const question = learningQuestion(questionId);
      if (!question || !value || typeof value !== "object") continue;
      const entry = value as Record<string, unknown>;
      const dateKey = dateKeyOrNull(entry.dateKey);
      if (!dateKey || !question.options.some((option) => option.id === entry.answerId)) continue;
      state.answers[questionId] = {
        answerId: entry.answerId as string,
        version: Math.max(1, Math.floor(Number(entry.version) || 1)),
        dateKey,
        answeredAtMs: positiveMs(entry.answeredAtMs) ?? 0,
      };
    }
  }
  state.initialCompletedAtMs = positiveMs(data.initialCompletedAtMs);
  const daily = (data.daily ?? {}) as Record<string, unknown>;
  state.daily = {
    dateKey: dateKeyOrNull(daily.dateKey),
    questionSetId: typeof daily.questionSetId === "string" ? daily.questionSetId : null,
    questionIds: questionIdsOrNull(daily.questionIds),
    kind: daily.kind === "onboarding" || daily.kind === "core" ? daily.kind : null,
    completedAtMs: positiveMs(daily.completedAtMs),
    skippedAtMs: positiveMs(daily.skippedAtMs),
  };
  state.completedDays = Math.max(0, Math.floor(Number(data.completedDays) || 0));
  const counts = (data.answerCounts ?? {}) as Record<string, unknown>;
  for (const [month, count] of Object.entries(counts)) {
    const n = Math.floor(Number(count));
    if (/^\d{4}-\d{2}$/.test(month) && n > 0) state.answerCounts[month] = n;
  }
  const journey = (data.journey ?? {}) as Record<string, unknown>;
  state.journey = {humorSkippedAtMs: positiveMs(journey.humorSkippedAtMs)};
  const window = data.writeWindow as Record<string, unknown> | undefined;
  const startMs = positiveMs(window?.startMs);
  state.writeWindow = startMs === null ? null : {startMs, count: Math.max(0, Number(window?.count) || 0)};
  return state;
}

export function serializeLearningState(state: LearningState): Record<string, unknown> {
  return {
    schemaVersion: LEARNING_STATE_SCHEMA_VERSION,
    required: state.required,
    answers: state.answers,
    initialCompletedAtMs: state.initialCompletedAtMs,
    daily: state.daily,
    completedDays: state.completedDays,
    answerCounts: state.answerCounts,
    journey: state.journey,
    writeWindow: state.writeWindow,
  };
}

// ---------------------------------------------------------------------------
// Today.
// ---------------------------------------------------------------------------

/**
 * Question ids of `set` the member has answered. A set is only ever made of
 * questions that were open when the day started, so an answer in the current
 * version was given while the set was live.
 */
export function answeredToday(state: LearningState, set: DailySet): string[] {
  return set.questions
    .filter((ref) => state.answers[ref.id]?.version === ref.version)
    .map((ref) => ref.id);
}

export function isDayCompleted(state: LearningState, dateKey: string): boolean {
  return state.daily.dateKey === dateKey && state.daily.completedAtMs !== null;
}

export function isDaySkipped(state: LearningState, dateKey: string): boolean {
  return state.daily.dateKey === dateKey && state.daily.skippedAtMs !== null;
}

/** Whether the member's daily Picks must wait for the onboarding questions (Q1-Q15). */
export function isLearningBlockingPicks(state: LearningState): boolean {
  return state.required && !hasFinishedOnboarding(state);
}

/** A new member's onboarding questions cannot be skipped. */
export function canSkipToday(state: LearningState): boolean {
  return !isLearningBlockingPicks(state);
}

/**
 * Where a member is in the first-run / daily journey, from facts only:
 *
 *   new member:  basic profile (onboarding) -> humor -> daily -> done
 *   every day:   daily (until today's set is done or skipped) -> done
 *
 * Humor counts as passed once calibrated or explicitly skipped, so a skip can
 * never loop. A day with nothing to ask is done. Deterministic: same facts,
 * same stage.
 */
export type JourneyStage = "humor" | "daily" | "done";

/** Nothing is left to do in `set`: it was completed, or there was nothing to ask. */
function isSetDone(state: LearningState, set: DailySet): boolean {
  return set.questions.length === 0 || isDayCompleted(state, set.dateKey);
}

export function journeyStage(state: LearningState, humorCalibrated: boolean, set: DailySet): JourneyStage {
  if (state.required && !humorCalibrated && state.journey.humorSkippedAtMs === null) return "humor";
  if (!isSetDone(state, set) && !isDaySkipped(state, set.dateKey)) return "daily";
  return "done";
}

/** The compact progress block other surfaces (Picks, the journey) carry. */
export function learningSummary(
  state: LearningState,
  set: DailySet,
  nowMs: number,
  facts?: {humorCalibrated: boolean},
): Record<string, unknown> {
  return {
    required: state.required,
    blocksPicks: isLearningBlockingPicks(state),
    firstSetCompleted: hasFinishedOnboarding(state),
    ...(facts
      ? {humorCalibrated: facts.humorCalibrated, journeyStage: journeyStage(state, facts.humorCalibrated, set)}
      : {}),
    today: {
      dateKey: set.dateKey,
      questionSetId: set.questionSetId,
      kind: set.kind,
      total: set.questions.length,
      answered: answeredToday(state, set).length,
      completed: isSetDone(state, set),
      skipped: isDaySkipped(state, set.dateKey),
      canSkip: canSkipToday(state),
    },
    nextDayStartsAtMs: nextLearningDayStartMs(nowMs),
  };
}

// ---------------------------------------------------------------------------
// Answering today's set.
// ---------------------------------------------------------------------------

export type AnswerRejection =
  | "stale-set"
  | "not-in-set"
  | "wrong-version"
  | "invalid-answer"
  | "rate-limited";

export type AnswerOutcome =
  | {ok: false; reason: AnswerRejection}
  | {
      ok: true;
      changed: boolean;
      state: LearningState;
      completedTodayNow: boolean;
      firstSetCompletedNow: boolean;
    };

function consumeWriteWindow(state: LearningState, nowMs: number): LearningState["writeWindow"] | null {
  const window = state.writeWindow && nowMs - state.writeWindow.startMs < ANSWER_WRITE_LIMIT.windowMs
    ? state.writeWindow
    : {startMs: nowMs, count: 0};
  if (window.count >= ANSWER_WRITE_LIMIT.max) return null;
  return {startMs: window.startMs, count: window.count + 1};
}

/** Today's markers with the set frozen onto them. */
function frozenDaily(current: LearningState, set: DailySet): LearningState["daily"] {
  const touchedToday = current.daily.dateKey === set.dateKey;
  return {
    dateKey: set.dateKey,
    questionSetId: set.questionSetId,
    questionIds: set.questions.map((ref) => ref.id),
    kind: set.kind,
    completedAtMs: touchedToday ? current.daily.completedAtMs : null,
    skippedAtMs: touchedToday ? current.daily.skippedAtMs : null,
  };
}

/**
 * Applies one answer to the member's set for today. Everything the client
 * says is checked against the server's set for the server's day: a set id
 * from another day (earlier, later or invented), a question outside the set —
 * tomorrow's Core questions included — a stale version or a foreign option is
 * rejected.
 *
 * The first answer of the day freezes the set onto the state, so the rest of
 * the day keeps asking the same questions.
 *
 * Idempotent: re-sending the same answer changes nothing (no write, no second
 * count, no second completion). A different answer to the same question
 * replaces the earlier one — members may change their mind.
 */
export function applyDailyAnswer(
  current: LearningState,
  set: DailySet,
  input: {questionSetId: unknown; questionId: unknown; questionVersion: unknown; answerId: unknown},
  nowMs: number,
): AnswerOutcome {
  if (input.questionSetId !== set.questionSetId) return {ok: false, reason: "stale-set"};
  const ref = set.questions.find((q) => q.id === input.questionId);
  if (!ref) return {ok: false, reason: "not-in-set"};
  const question = learningQuestion(ref.id);
  if (!question || !question.active || question.version !== ref.version ||
      input.questionVersion !== ref.version) {
    return {ok: false, reason: "wrong-version"};
  }
  if (!question.options.some((option) => option.id === input.answerId)) {
    return {ok: false, reason: "invalid-answer"};
  }
  const existing = current.answers[question.id];
  const alreadyAnswered = existing?.version === question.version;
  if (alreadyAnswered && existing.answerId === input.answerId) {
    return {ok: true, changed: false, state: current, completedTodayNow: false, firstSetCompletedNow: false};
  }
  const window = consumeWriteWindow(current, nowMs);
  if (!window) return {ok: false, reason: "rate-limited"};

  const month = set.dateKey.slice(0, 7);
  const next: LearningState = {
    ...current,
    answers: {
      ...current.answers,
      [question.id]: {
        answerId: input.answerId as string,
        version: question.version,
        dateKey: set.dateKey,
        answeredAtMs: nowMs,
      },
    },
    daily: frozenDaily(current, set),
    answerCounts: alreadyAnswered
      ? current.answerCounts
      : {...current.answerCounts, [month]: (current.answerCounts[month] ?? 0) + 1},
    writeWindow: window,
  };

  let completedTodayNow = false;
  let firstSetCompletedNow = false;
  if (next.daily.completedAtMs === null && answeredToday(next, set).length === set.questions.length) {
    next.daily = {...next.daily, completedAtMs: nowMs};
    next.completedDays = current.completedDays + 1;
    completedTodayNow = true;
    if (next.initialCompletedAtMs === null) {
      next.initialCompletedAtMs = nowMs;
      firstSetCompletedNow = true;
    }
  }
  return {ok: true, changed: true, state: next, completedTodayNow, firstSetCompletedNow};
}

/**
 * Changes an EARLIER answer (the learning dashboard). Only questions the
 * member already answered, only in their current version: this is how
 * preferences change over time, never a way to answer questions outside the
 * daily set. The answer keeps the day it was given on.
 */
export function updateEarlierAnswer(
  current: LearningState,
  input: {questionId: unknown; questionVersion: unknown; answerId: unknown},
  nowMs: number,
): {ok: false; reason: "not-answered" | "wrong-version" | "invalid-answer" | "rate-limited"} |
  {ok: true; changed: boolean; state: LearningState} {
  const question = learningQuestion(input.questionId);
  const existing = question ? current.answers[question.id] : undefined;
  if (!question || !question.active || !existing) return {ok: false, reason: "not-answered"};
  if (input.questionVersion !== question.version || existing.version !== question.version) {
    return {ok: false, reason: "wrong-version"};
  }
  if (!question.options.some((option) => option.id === input.answerId)) {
    return {ok: false, reason: "invalid-answer"};
  }
  if (existing.answerId === input.answerId) return {ok: true, changed: false, state: current};
  const window = consumeWriteWindow(current, nowMs);
  if (!window) return {ok: false, reason: "rate-limited"};
  return {
    ok: true,
    changed: true,
    state: {
      ...current,
      answers: {...current.answers, [question.id]: {...existing, answerId: input.answerId as string, answeredAtMs: nowMs}},
      writeWindow: window,
    },
  };
}

/**
 * "Bugünlük geç": hides today's set until tomorrow. Not for a new member's
 * onboarding questions. Skipping does not advance the sequence: the questions
 * left open come back first.
 */
export function skipToday(
  current: LearningState,
  set: DailySet,
  nowMs: number,
): {ok: false; reason: "first-set-required"} | {ok: true; state: LearningState} {
  if (!canSkipToday(current)) return {ok: false, reason: "first-set-required"};
  if (isDaySkipped(current, set.dateKey) || isSetDone(current, set)) {
    return {ok: true, state: current};
  }
  return {ok: true, state: {...current, daily: {...frozenDaily(current, set), skippedAtMs: nowMs}}};
}

// ---------------------------------------------------------------------------
// Declared preferences.
// ---------------------------------------------------------------------------

/**
 * Existing profile information that already says something about an area.
 * Reused for dashboard coverage, so nobody is asked twice for what Mevora
 * already knows.
 */
export interface ProfileSignals {
  hasRelationshipGoal: boolean;
  hasLifestyle: boolean;
  hasInterests: boolean;
  hasMusic: boolean;
  humorReady: boolean;
  relationshipAnswerCount: number;
}

export function noProfileSignals(): ProfileSignals {
  return {
    hasRelationshipGoal: false,
    hasLifestyle: false,
    hasInterests: false,
    hasMusic: false,
    humorReady: false,
    relationshipAnswerCount: 0,
  };
}

/**
 * The member's declared weight per dimension: 1.00 unless an importance
 * question says how much that dimension matters to them. Answers to retired
 * questions carry no weight.
 */
export function declaredAdjustments(state: LearningState): Adjustments {
  const out = {} as Adjustments;
  for (const dimension of PERSONALIZATION_DIMENSIONS) out[dimension] = ADJUSTMENT_BOUNDS.neutral;
  for (const [questionId, answer] of Object.entries(state.answers)) {
    const question = learningQuestion(questionId);
    if (!question || !question.active || !isImportanceQuestion(question)) continue;
    const value = question.options.find((option) => option.id === answer.answerId)?.value;
    const weight = value === undefined ? undefined : DECLARED_IMPORTANCE[value];
    if (weight !== undefined) out[question.dimension] = weight;
  }
  return out;
}

/** Answers the pair scorer may compare, keyed by question id. */
export function comparableAnswers(state: LearningState): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [questionId, answer] of Object.entries(state.answers)) {
    const question = learningQuestion(questionId);
    if (question?.active && !isImportanceQuestion(question) && answer.version === question.version) {
      out[questionId] = answer.answerId;
    }
  }
  return out;
}
