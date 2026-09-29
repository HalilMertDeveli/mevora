/**
 * Relationship Learning — every tunable number in one place.
 *
 * Nothing here runs on a clock. Follow-up questions become available after a
 * quiet period measured from the member's own last answers, and are only
 * ever offered when the member opens the app; there is no scheduler, no
 * push and no hourly anything.
 */

const DAY_MS = 86_400_000;

export const LEARNING_STATE_SCHEMA_VERSION = 1;

export const PROGRESSIVE = {
  /** Questions per follow-up round ("3 kısa soru"). */
  batchSize: 3,
  /** The first follow-up round waits this long after the initial set. */
  firstDelayMs: DAY_MS,
  /** A finished round is followed by at least this much quiet. */
  intervalMs: 3 * DAY_MS,
  /** "Not now" hides the prompt for this long. The questions stay answerable. */
  snoozeMs: 3 * DAY_MS,
} as const;

/**
 * Declared importance -> the member's declared weight for that dimension.
 * Inside the personalization band (0.70-1.30) with room to spare, so what the
 * member later shows through their connections can still move it.
 */
export const DECLARED = {
  importance: {high: 1.15, medium: 1.0, low: 0.88},
  /** Each answer about a dimension adds this much declared confidence. */
  confidencePerAnswer: 0.25,
  /** Each existing profile signal for a dimension adds this much. */
  confidencePerProfileSignal: 0.25,
} as const;

/** Per-member write budget for answers: generous for real use, bounded for loops. */
export const ANSWER_WRITE_LIMIT = {
  windowMs: 10 * 60 * 1000,
  max: 120,
} as const;
