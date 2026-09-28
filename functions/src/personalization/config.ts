/**
 * Adaptive personalization — every tunable number in one place.
 *
 * Mevora learns, slowly and within hard bounds, how much each EXISTING
 * compatibility dimension appears to matter to one member, from what happens
 * after they meet people: likes, matches, and above all whether conversations
 * start and last. It never learns anything about a person that the
 * compatibility engine does not already measure, never reads message content,
 * and never touches eligibility or safety.
 *
 * Deterministic arithmetic only. No model, no randomness, no external call.
 */

/** Bump when the learned state's meaning changes, so V2 can detect V1 state. */
export const PERSONALIZATION_ALGORITHM_VERSION = 1;

/**
 * The personalizable dimensions: the canonical compatibility dimensions the
 * engine already measures (see PickSignals / calculateCompatibility). Distance
 * is deliberately absent — it stays a hard filter and a preferred radius.
 */
export const PERSONALIZATION_DIMENSIONS = [
  "relationship",
  "values",
  "lifestyle",
  "interests",
  "music",
  "humor",
] as const;
export type PersonalizationDimension = (typeof PERSONALIZATION_DIMENSIONS)[number];

/** Observed adjustment per dimension. Neutral is 1.00; it can never leave the band. */
export const ADJUSTMENT_BOUNDS = {
  min: 0.7,
  neutral: 1.0,
  max: 1.3,
} as const;

export const LEARNING = {
  /**
   * Pseudo-observations of "no preference" every dimension starts with. The
   * learned direction is the evidence-weighted mean shrunk toward neutral by
   * this prior, so a new member's first few interactions barely register.
   */
  priorEvidence: 24,
  /** A perfectly consistent mean of ±1 would move the target this far from 1.00. */
  gain: 0.35,
  /** No single event may move an adjustment further than this. */
  maxStepPerEvent: 0.03,
  /** Old evidence fades with this half-life, so preferences can evolve. */
  halfLifeDays: 120,
  /**
   * A candidate within this distance of the neutral 50 on a dimension says
   * nothing about that dimension (centred magnitude below this is ignored).
   */
  minCentredMagnitude: 0.1,
} as const;

/**
 * Event strengths. Sign is the outcome's direction for the member: positive
 * means "this went well", negative means "this went badly".
 *
 * Ordering is the point: what happens after a match matters more than the
 * like itself. Report, block and safety events are deliberately absent — they
 * belong to moderation, never to romantic preference learning.
 */
export const SIGNAL_STRENGTHS = {
  /** Contrast for likes: shown, looked at, declined. Weak on purpose. */
  pass: -0.4,
  like: 1.0,
  superLike: 2.0,
  match: 2.0,
  /** Both people have written at least once. */
  conversationStarted: 3.0,
  /** Still writing a day after it started. */
  conversationSurvived: 4.0,
  /** Mutual activity on a second distinct day. */
  secondSession: 4.5,
  /** Meaningful, but many unmatches have nothing to do with compatibility. */
  unmatch: -2.0,
  /**
   * Reserved for an explicit, structured post-match rating. Mevora's current
   * post-match feedback is free text only, which this feature must not
   * analyse, so nothing emits these yet.
   */
  postMatchFeedbackPositive: 5.0,
  postMatchFeedbackNegative: -5.0,
} as const;

export type StrongSignalType = Exclude<
  keyof typeof SIGNAL_STRENGTHS,
  "postMatchFeedbackPositive" | "postMatchFeedbackNegative"
>;

/**
 * Weak profile-engagement signals. One aggregated event per viewer, candidate
 * and day, whatever happened on the profile — so repeated opens cannot farm
 * evidence — and its total is capped far below a single like.
 */
export const WEAK_SIGNALS = {
  detailsOpened: 0.04,
  photosBrowsed: 0.02,
  spotifyOpened: 0.04,
  whyThisPersonOpened: 0.04,
  /** Foreground dwell, bucketed. Anything past `ignoreAboveMs` is treated as idle. */
  dwell: {
    bucketsMs: [3_000, 10_000, 30_000] as const,
    strengths: [0, 0.02, 0.04, 0.06] as const,
    ignoreAboveMs: 120_000,
  },
  /** Ceiling for one engagement event, all parts together. */
  maxTotal: 0.15,
  /** At most this many engagement events count per member per day. */
  maxEventsPerDay: 40,
} as const;

/**
 * Ranking. The learned adjustment re-weights each dimension's deviation from
 * neutral, then the result is added to the canonical overall score as a
 * bounded ranking term. The public compatibility percentage never changes.
 */
export const RANKING = {
  /** Points per unit of (adjustment − 1) × centred dimension score. */
  pointsPerUnit: 20,
  /** One dimension can never move a candidate by more than this. */
  maxDimensionPoints: 6,
  /** All dimensions together can never move a candidate by more than this. */
  maxTotalPoints: 10,
  /** Below this, a dimension's adjustment counts as "not learned yet". */
  activeThreshold: 0.02,
} as const;

/**
 * Exploration keeps the member from being trapped in their own pattern: a
 * minority of Picks come from strong candidates the learned preferences do
 * NOT favour. They pass every hard filter and the normal quality floor.
 */
export const EXPLORATION = {
  /** Share of a batch reserved for exploration once personalization is active. */
  ratio: 0.15,
  /** A batch that explores at all explores at least this many slots. */
  minSlots: 1,
  /** Exploration candidates need a strong base score on their own. */
  minOverall: 68,
  /** Hash jitter (0..jitterPoints) so the exploration pick rotates between batches. */
  jitterPoints: 4,
} as const;

/** How long an event-ledger entry is kept for idempotency. */
export const EVENT_LEDGER_TTL_DAYS = 180;
