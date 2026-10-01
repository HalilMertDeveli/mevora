/**
 * Relationship questions — every tunable number in one place.
 *
 * Nothing here runs on a clock. A member's set for the day is worked out from
 * their own answers when they ask for it; there is no scheduler, no push and
 * no hourly anything.
 */

export const LEARNING_STATE_SCHEMA_VERSION = 3;

export const DAILY = {
  /**
   * The logical day: midnight at this UTC offset (Europe/Istanbul, no DST),
   * decided on the SERVER clock — the same convention as daily Picks. A
   * device clock or time zone can never move a member into another day.
   */
  utcOffsetMinutes: 180,
} as const;

/**
 * How the Core sequence (coreSequence.ts) is handed out. Both numbers are
 * product rules, not tuning: see docs/MATCHING_PRODUCT_RULES.md.
 */
export const CORE = {
  /** Q1..Q15 are onboarding: asked first, in order, before the first Picks. */
  onboardingCount: 15,
  /** Core questions per logical day after onboarding. Never more. */
  dailyCount: 5,
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
