/**
 * Relationship questions — every tunable number in one place.
 *
 * Nothing here runs on a clock. The daily set is chosen when the first member
 * of the day asks for it; there is no scheduler, no push and no hourly
 * anything.
 */

export const LEARNING_STATE_SCHEMA_VERSION = 2;

export const DAILY = {
  /**
   * The logical day: midnight at this UTC offset (Europe/Istanbul, no DST),
   * decided on the SERVER clock — the same convention as daily Picks. A
   * device clock or time zone can never move a member into another day.
   */
  utcOffsetMinutes: 180,
  /** Day 0 of the rotation. Changing it reshuffles every future day. */
  anchorDateKey: "2026-09-01",
  /** Bump when the rotation rule changes; part of every questionSetId. */
  scheduleVersion: 1,
} as const;

/**
 * Declared importance (answer position 1..5) -> the member's declared weight
 * for that dimension. Inside the personalization band (0.70-1.30) with room
 * to spare, so what the member later shows through their connections can
 * still move it.
 */
export const DECLARED_IMPORTANCE: Record<number, number> = {
  1: 0.88,
  2: 0.94,
  3: 1.0,
  4: 1.08,
  5: 1.15,
};

/**
 * Shared-answer evidence. A pair's question score is shrunk toward the
 * neutral 50 until enough answers are shared:
 *
 *   score = 50 + (raw - 50) * shared / (shared + priorSharedAnswers)
 *
 * 10 shared answers keep two thirds of the signal, 100 keep 95%, 300 keep 98%.
 */
export const EVIDENCE = {
  priorSharedAnswers: 5,
  /** Agreement at or above this counts as an aligned view for explanations. */
  alignedAtLeast: 0.75,
} as const;

/** Per-member write budget for answers: generous for real use, bounded for loops. */
export const ANSWER_WRITE_LIMIT = {
  windowMs: 10 * 60 * 1000,
  max: 120,
} as const;
