import {
  ADJUSTMENT_BOUNDS,
  PERSONALIZATION_DIMENSIONS,
  type PersonalizationDimension,
} from "../personalization/config.js";
import type {Adjustments} from "../personalization/learner.js";
import {
  INITIAL_QUESTION_COUNT,
  initialQuestions,
  learningQuestion,
  progressiveQuestions,
  type LearningQuestion,
  type LearningStage,
} from "./catalog.js";
import {ANSWER_WRITE_LIMIT, DECLARED, LEARNING_STATE_SCHEMA_VERSION, PROGRESSIVE} from "./config.js";

/**
 * Relationship Learning state and the pure rules over it. Nothing here reads
 * Firestore, the wall clock or a random source: the same state and clock
 * always give the same questions, the same declared weights and the same
 * completion.
 */

export interface StoredAnswer {
  answerId: string;
  /** The question version the member actually saw. */
  version: number;
  source: LearningStage;
  answeredAtMs: number;
}

export interface LearningState {
  exists: boolean;
  schemaVersion: number;
  /**
   * True for members who finished onboarding after Relationship Learning
   * shipped: their daily Picks wait for the initial set. Existing members are
   * invited, never blocked.
   */
  required: boolean;
  answers: Record<string, StoredAnswer>;
  initialCompletedAtMs: number | null;
  progressive: {
    /** The current follow-up round, stable until answered. */
    batch: string[];
    batchCreatedAtMs: number | null;
    lastBatchCompletedAtMs: number | null;
    snoozedUntilMs: number | null;
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
    progressive: {batch: [], batchCreatedAtMs: null, lastBatchCompletedAtMs: null, snoozedUntilMs: null},
    writeWindow: null,
  };
}

function positiveMs(value: unknown): number | null {
  const n = Number(value);
  return value !== null && value !== undefined && Number.isFinite(n) && n > 0 ? n : null;
}

/**
 * Reads a stored state defensively. Unknown questions, foreign answer ids and
 * malformed entries are dropped rather than trusted.
 */
export function parseLearningState(raw: unknown): LearningState {
  const state = emptyLearningState();
  if (!raw || typeof raw !== "object") return state;
  const data = raw as Record<string, unknown>;
  state.exists = true;
  state.schemaVersion = Number(data.schemaVersion) || LEARNING_STATE_SCHEMA_VERSION;
  state.required = data.required === true;
  const answers = (data.answers ?? {}) as Record<string, unknown>;
  if (answers && typeof answers === "object") {
    for (const [questionId, value] of Object.entries(answers)) {
      const question = learningQuestion(questionId);
      if (!question || !value || typeof value !== "object") continue;
      const entry = value as Record<string, unknown>;
      const answerId = entry.answerId;
      if (!question.options.some((option) => option.id === answerId)) continue;
      state.answers[questionId] = {
        answerId: answerId as string,
        version: Math.max(1, Math.floor(Number(entry.version) || 1)),
        source: entry.source === "progressive" ? "progressive" : "initial",
        answeredAtMs: positiveMs(entry.answeredAtMs) ?? 0,
      };
    }
  }
  state.initialCompletedAtMs = positiveMs(data.initialCompletedAtMs);
  const progressive = (data.progressive ?? {}) as Record<string, unknown>;
  state.progressive = {
    batch: Array.isArray(progressive.batch)
      ? (progressive.batch as unknown[])
        .filter((id): id is string => typeof id === "string" && learningQuestion(id)?.stage === "progressive")
        .slice(0, PROGRESSIVE.batchSize)
      : [],
    batchCreatedAtMs: positiveMs(progressive.batchCreatedAtMs),
    lastBatchCompletedAtMs: positiveMs(progressive.lastBatchCompletedAtMs),
    snoozedUntilMs: positiveMs(progressive.snoozedUntilMs),
  };
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
    progressive: state.progressive,
    writeWindow: state.writeWindow,
  };
}

// ---------------------------------------------------------------------------
// Progress.
// ---------------------------------------------------------------------------

export function initialAnsweredCount(state: LearningState): number {
  return initialQuestions().filter((question) => state.answers[question.id]).length;
}

export function isInitialComplete(state: LearningState): boolean {
  return state.initialCompletedAtMs !== null;
}

/** Whether the member's daily Picks must wait for the initial set. */
export function isLearningBlockingPicks(state: LearningState): boolean {
  return state.required && !isInitialComplete(state);
}

/** The compact progress block other surfaces (Picks) carry. */
export function learningSummary(state: LearningState, nowMs: number): Record<string, unknown> {
  return {
    required: state.required,
    initialTotal: INITIAL_QUESTION_COUNT,
    initialAnswered: initialAnsweredCount(state),
    initialCompleted: isInitialComplete(state),
    blocksPicks: isLearningBlockingPicks(state),
    progressiveDue: isProgressivePromptDue(state, nowMs),
    followUpSize: PROGRESSIVE.batchSize,
  };
}

// ---------------------------------------------------------------------------
// Answering.
// ---------------------------------------------------------------------------

export type AnswerOutcome =
  | {ok: false; reason: "invalid-question" | "invalid-answer" | "rate-limited"}
  | {
      ok: true;
      changed: boolean;
      state: LearningState;
      completedInitialNow: boolean;
      completedBatchNow: boolean;
    };

/**
 * Applies one answer. Idempotent: re-sending the same answer changes nothing
 * (no write, no double count, no second completion). A different answer to
 * the same question replaces the earlier one — members may change their mind.
 */
export function applyAnswer(
  current: LearningState,
  questionId: unknown,
  answerId: unknown,
  nowMs: number,
): AnswerOutcome {
  const question = learningQuestion(questionId);
  if (!question || !question.active) return {ok: false, reason: "invalid-question"};
  if (!question.options.some((option) => option.id === answerId)) {
    return {ok: false, reason: "invalid-answer"};
  }
  const existing = current.answers[question.id];
  if (existing && existing.answerId === answerId && existing.version === question.version) {
    return {ok: true, changed: false, state: current, completedInitialNow: false, completedBatchNow: false};
  }

  const window = current.writeWindow && nowMs - current.writeWindow.startMs < ANSWER_WRITE_LIMIT.windowMs
    ? current.writeWindow
    : {startMs: nowMs, count: 0};
  if (window.count >= ANSWER_WRITE_LIMIT.max) return {ok: false, reason: "rate-limited"};

  const next: LearningState = {
    ...current,
    answers: {
      ...current.answers,
      [question.id]: {
        answerId: answerId as string,
        version: question.version,
        source: question.stage,
        answeredAtMs: nowMs,
      },
    },
    progressive: {...current.progressive, batch: [...current.progressive.batch]},
    writeWindow: {startMs: window.startMs, count: window.count + 1},
  };

  let completedInitialNow = false;
  if (next.initialCompletedAtMs === null && initialAnsweredCount(next) >= INITIAL_QUESTION_COUNT) {
    next.initialCompletedAtMs = nowMs;
    completedInitialNow = true;
  }

  let completedBatchNow = false;
  const batch = next.progressive.batch;
  if (batch.length > 0 && batch.includes(question.id) && batch.every((id) => next.answers[id])) {
    next.progressive = {
      ...next.progressive,
      batch: [],
      batchCreatedAtMs: null,
      lastBatchCompletedAtMs: nowMs,
    };
    completedBatchNow = true;
  }
  return {ok: true, changed: true, state: next, completedInitialNow, completedBatchNow};
}

// ---------------------------------------------------------------------------
// Declared preferences.
// ---------------------------------------------------------------------------

/**
 * Existing profile information that already says something about a
 * dimension. Reused, so nobody is asked twice for what Mevora already knows.
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
 * The member's declared weight per dimension: 1.00 unless they told Mevora
 * how much that dimension matters to them.
 */
export function declaredAdjustments(state: LearningState): Adjustments {
  const out = {} as Adjustments;
  for (const dimension of PERSONALIZATION_DIMENSIONS) out[dimension] = ADJUSTMENT_BOUNDS.neutral;
  for (const [questionId, answer] of Object.entries(state.answers)) {
    const question = learningQuestion(questionId);
    if (!question || question.kind !== "importance") continue;
    const level = question.options.find((option) => option.id === answer.answerId)?.importance;
    if (level) out[question.dimension] = DECLARED.importance[level];
  }
  return out;
}

/** How well Mevora knows each dimension from what the member TOLD it, 0..1. */
export function declaredConfidence(
  state: LearningState,
  signals: ProfileSignals,
): Record<PersonalizationDimension, number> {
  const raw = {} as Record<PersonalizationDimension, number>;
  for (const dimension of PERSONALIZATION_DIMENSIONS) raw[dimension] = 0;
  for (const questionId of Object.keys(state.answers)) {
    const question = learningQuestion(questionId);
    if (question) raw[question.dimension] += DECLARED.confidencePerAnswer;
  }
  const bump = (dimension: PersonalizationDimension, times = 1) => {
    raw[dimension] += DECLARED.confidencePerProfileSignal * times;
  };
  if (signals.hasRelationshipGoal) bump("relationship");
  if (signals.hasLifestyle) bump("lifestyle");
  if (signals.hasInterests) bump("interests");
  if (signals.hasMusic) bump("music");
  if (signals.humorReady) bump("humor");
  if (signals.relationshipAnswerCount >= 9) bump("values", 2);
  else if (signals.relationshipAnswerCount >= 3) bump("values");
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    raw[dimension] = Math.min(1, Math.round(raw[dimension] * 1000) / 1000);
  }
  return raw;
}

// ---------------------------------------------------------------------------
// Progressive questions.
// ---------------------------------------------------------------------------

/**
 * The next follow-up questions: unanswered ones about the dimensions Mevora
 * knows least about. Greedy and deterministic — after each pick the chosen
 * dimension counts as a little better known, so one round spreads across
 * weak dimensions instead of asking three music questions in a row. Ties go
 * to catalog order.
 */
export function selectProgressiveQuestions(
  state: LearningState,
  confidence: Record<PersonalizationDimension, number>,
  count: number = PROGRESSIVE.batchSize,
): LearningQuestion[] {
  const pool = progressiveQuestions().filter((question) => !state.answers[question.id]);
  const known = {...confidence};
  const chosen: LearningQuestion[] = [];
  while (chosen.length < count && pool.length > 0) {
    let bestIndex = 0;
    for (let i = 1; i < pool.length; i++) {
      const a = pool[i];
      const b = pool[bestIndex];
      const byConfidence = known[a.dimension] - known[b.dimension];
      if (byConfidence < 0 || (byConfidence === 0 && a.order < b.order)) bestIndex = i;
    }
    const [question] = pool.splice(bestIndex, 1);
    chosen.push(question);
    known[question.dimension] += DECLARED.confidencePerAnswer;
  }
  return chosen;
}

/**
 * Creates the next round when there is none. Rounds exist only after the
 * initial set; a round, once created, stays the same until answered.
 */
export function ensureProgressiveBatch(
  state: LearningState,
  confidence: Record<PersonalizationDimension, number>,
  nowMs: number,
): {state: LearningState; created: boolean} {
  if (!isInitialComplete(state)) return {state, created: false};
  const open = state.progressive.batch.filter((id) => !state.answers[id]);
  if (open.length > 0) return {state, created: false};
  const questions = selectProgressiveQuestions(state, confidence);
  if (questions.length === 0) return {state, created: false};
  return {
    state: {
      ...state,
      progressive: {
        ...state.progressive,
        batch: questions.map((question) => question.id),
        batchCreatedAtMs: nowMs,
      },
    },
    created: true,
  };
}

/**
 * Whether Mevora should invite the member to the current round now. Never
 * on a timer: only when they open the app, only after quiet periods measured
 * from their own last round, and never while "not now" is running.
 */
export function isProgressivePromptDue(state: LearningState, nowMs: number): boolean {
  if (state.initialCompletedAtMs === null) return false;
  if (!state.progressive.batch.some((id) => !state.answers[id])) return false;
  if (nowMs - state.initialCompletedAtMs < PROGRESSIVE.firstDelayMs) return false;
  const last = state.progressive.lastBatchCompletedAtMs;
  if (last !== null && nowMs - last < PROGRESSIVE.intervalMs) return false;
  const snoozed = state.progressive.snoozedUntilMs;
  if (snoozed !== null && nowMs < snoozed) return false;
  return true;
}

/** Stance answers the pair scorer may compare, keyed by question id. */
export function comparableAnswers(state: LearningState): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [questionId, answer] of Object.entries(state.answers)) {
    if (learningQuestion(questionId)?.kind === "stance") out[questionId] = answer.answerId;
  }
  return out;
}
